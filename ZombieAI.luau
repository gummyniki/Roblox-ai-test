local replicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local tweenService = game:GetService("TweenService")

local States = {}
local baseAI = {}
local StateMachine = {}
local ZombieAI = {}
local pathing = {}
local combat = {}

---------------------------------------------
-- State Machine
---------------------------------------------

StateMachine.__index = StateMachine

function StateMachine.new(initialState)
	return setmetatable({
		current = initialState,
		previous = nil,
		states = {}
	}, StateMachine)
end

function StateMachine:AddState(name, state)
	self.states[name] = state
end

function StateMachine:Get()
	return self.current
end


function StateMachine:Change(newState)
	if self.current == newState then return end

	local oldState = self.current
	self.previous = oldState

	-- exit old state
	if oldState and self.states[oldState] and self.states[oldState].Exit then
		self.states[oldState].Exit()
	end

	self.current = newState

	-- enter new state
	if self.states[newState] and self.states[newState].Enter then
		self.states[newState].Enter()
	end
end

function StateMachine:Update(dt)
	local state = self.states[self.current]
	if state and state.Update then
		state.Update(dt)
	end
end

---------------------------------------------
-- Pathing
--------------------------------------------

function pathing.FollowTarget(ai, destination)
	local path = PathfindingService:FindPathAsync(ai.root.Position, destination)
	local currentPointIndex = 1

	local TargetOffsetMax = 10
	local JumpThreshold = 1.5
	local NextPointThreshold = 4

	if path.Status ~= Enum.PathStatus.Success then
		warn("Unable to compute path! Status: ".. tostring(path.Status))
	end

	if path then
		local points = path:GetWaypoints()
		if currentPointIndex < #points then
			local currentPoint = points[currentPointIndex]
			local distance = (ai.character.HumanoidRootPart.Position - currentPoint.Position).magnitude
			if distance < NextPointThreshold then
				currentPointIndex = currentPointIndex + 1
			end

			ai.character.Humanoid:MoveTo(points[currentPointIndex].Position)
			if points[currentPointIndex].Position.Y - ai.character.HumanoidRootPart.Position.Y > JumpThreshold then
				ai.character.Humanoid.Jump = true
			end
		else
			ai.character.Humanoid:MoveTo(destination)
		end
	end
end


function pathing.hasLineOfSight(from, to, targetCharacter, ignore)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore

	local direction = to - from
	local result = workspace:Raycast(from, direction, params)


	if not result then
		return false
	end

	return result.Instance:IsDescendantOf(targetCharacter)
end


function pathing.getNearestPlayer(character: Model, maxRange: number)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local closestCharacter = nil
	local closestDistance = maxRange

	for _, player in game.Players:GetPlayers() do
		local character = player.Character
		if not character then continue end

		local humanoid = character:FindFirstChild("Humanoid")
		local charRoot = character:FindFirstChild("HumanoidRootPart")

		if not humanoid or not charRoot then continue end
		if humanoid.Health <= 0 then continue end

		local distance = (charRoot.Position - root.Position).Magnitude

		if distance < closestDistance then
			closestDistance = distance
			closestCharacter = character
		end
	end

	return closestCharacter
end


function pathing.moveToRandomPoint(ai, debugging: boolean)
	local humanoid = ai.character:FindFirstChild("Humanoid")
	local root = ai.character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	if ai.state:Get() ~= "Wander" then return end


	if ai.moveConnection then
		ai.moveConnection:Disconnect()
		ai.moveConnection = nil
	end

	ai.isWandering = true


	local path = PathfindingService:CreatePath()
	path:ComputeAsync(
		root.Position,
		Vector3.new(math.random(-50, 50), root.Position.Y, math.random(-50, 50))
	)

	if path.Status ~= Enum.PathStatus.Success then return end

	local waypoints = path:GetWaypoints()
	local index = 1

	ai.moveConnection = humanoid.MoveToFinished:Connect(function(reached)
		if not reached then
			ai.isNavigating = false
			ai.moveConnection:Disconnect()
			ai.moveConnection = nil
			return
		end

		index += 1
		if index > #waypoints then
			ai.isWandering = false
			ai.moveConnection:Disconnect()
			ai.moveConnection = nil
			ai.finishedWander = true
			return
		end

		humanoid:MoveTo(waypoints[index].Position)
	end)


	-- start movement
	humanoid:MoveTo(waypoints[index].Position)

	-- debugging visuals
	if debugging then
		for _, waypoint in waypoints do
			local p = Instance.new("Part")
			p.Size = Vector3.new(0.5, 0.5, 0.5)
			p.Shape = Enum.PartType.Ball
			p.Material = Enum.Material.Neon
			p.Anchored = true
			p.CanCollide = false
			p.Position = waypoint.Position
			p.Parent = workspace

			task.delay(5, function()
				p:Destroy()
			end)
		end
	end
end


---------------------------------------------
-- Combat
---------------------------------------------

function combat.RaycastHit(ai, range)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ai.character }

	local result = workspace:Raycast(
		ai.root.Position,
		ai.root.CFrame.LookVector * range,
		params
	)

	return result
end

function combat.BlockCastPart(part : BasePart, size : Vector3, offset : Vector3, params : RaycastParams)
	local baseParams = RaycastParams.new()
	baseParams.FilterType = Enum.RaycastFilterType.Exclude
	baseParams.FilterDescendantsInstances = {part}

	params = params or baseParams
	size = size or Vector3.new(1, 1, 1)
	offset = offset or Vector3.new(0, 0, 0)
	local blockcast = workspace:Blockcast(part.CFrame + offset, size, part.CFrame.LookVector, params)


	return blockcast


end

---------------------------------------------
-- Base AI
---------------------------------------------

baseAI.__index = baseAI

function baseAI.new(character, config)
	local self = setmetatable({}, baseAI)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")
	self.animator = self.humanoid:FindFirstChild("Animator")

	self.state = StateMachine.new("Idle")

	self.config = config
	self.target = nil

	self.lastAttackTime = 0
	self.isWandering = false

	self.animations = {}
	self.flags = {
		stunned = false,
		jumpscaring = false
	}

	return self
end

function baseAI:CanAttack()
	return os.clock() - self.lastAttackTime >= self.config.HitCooldown
end

function baseAI:Attack()
	self.lastAttackTime = os.clock()
end

function baseAI:SetTarget(target)
	self.target = target
end

function baseAI:ClearTarget()
	self.target = nil
end

function baseAI:Update(dt)
	self.state:Update(dt)
end

function baseAI:StopMovement()
	if self.moveConnection then
		self.moveConnection:Disconnect()
		self.moveConnection = nil
	end

	self.humanoid:Move(Vector3.zero)
end

function baseAI:RegisterAnimation(name, animation, looped)
	local track = self.animator:LoadAnimation(animation)
	track.Looped = looped
	self.animations[name] = track
	return track
end

function baseAI:InitCooldowns()
	self.cooldowns = {}
end

function baseAI:SetCooldown(name, duration)
	self.cooldowns[name] = os.clock() + duration
end

function baseAI:IsOnCooldown(name)
	local t = self.cooldowns[name]
	return t ~= nil and os.clock() < t
end

function baseAI:ClearCooldown(name)
	self.cooldowns[name] = nil
end


------------------------------------------------
-- Zombie States
------------------------------------------------


function States.BaseWander(ai, options)
	options = options or {}

	return {
		Enter = function()
			if not ai.canMove then return end
			ai.humanoid.WalkSpeed = ai.config.walkingSpeed
			pathing.moveToRandomPoint(ai, false)
		end,

		Update = function(dt)
			if not ai.canMove then return end
			if not ai.isWandering then
				pathing.moveToRandomPoint(ai, false)
			end

			local nearestChar = pathing.getNearestPlayer(ai.character, ai.config.HearingRange)

			if nearestChar then
				if pathing.hasLineOfSight(ai.root.Position, nearestChar:FindFirstChild("HumanoidRootPart").Position, nearestChar, {ai.character}) then
					ai:SetTarget(nearestChar)
					ai.state:Change("Chase")
				end
			end


		end,

		Exit = function()
			ai:StopMovement()
		end

	}
end

function States.BaseChase(ai, options)
	options = options or {}
	local enemy = options.Enemy or "Zombie"
	local attackRange = options.AttackRange or 2
	local chasePlayerEvent = options.chasePlayerEvent or game.ReplicatedStorage.Events.Zombie.ChasePlayer
	local stoppedChasePlayerEvent = options.StoppedChasePlayerEvent or game.ReplicatedStorage.Events.Zombie.StoppedChasingPlayer

	return {
		Enter = function()
			if not ai.canMove then return end
			ai.humanoid.WalkSpeed = ai.config.runningSpeed
			chasePlayerEvent:FireClient(game.Players:GetPlayerFromCharacter(ai.target), ai.root, enemy)
		end,	

		Update = function(dt)
			if not ai.canMove then return end
			if not ai.target then 
				ai.state:Change("Wander")
				return
			end

			pathing.FollowTarget(ai, ai.target:FindFirstChild("HumanoidRootPart").Position)

			if combat.RaycastHit(ai, attackRange) and ai:CanAttack() then
				ai:Attack()
			end


			local root = ai.root
			local targetRoot = ai.target:FindFirstChild("HumanoidRootPart")

			if not targetRoot then
				ai.state:Change("Wander")
				return
			end

			local distance = (root.Position - targetRoot.Position).Magnitude

			if distance > ai.config.HearingRange then
				ai.state:Change("Wander")
				return
			end
		end,

		Exit = function()
			local target = ai.target

			ai.target = nil



			if target then
				stoppedChasePlayerEvent:FireClient(game.Players:GetPlayerFromCharacter(target))
			end
		end

	}

end

function States.Idle(ai)
	return {
		Enter = function() end,
		Update = function() end,
		Exit = function() end
	}
end

function States.BaseStun(ai)
	return {
		Enter = function()
			if ai.flags.stunned then return end
			ai.flags.stunned = true

			ai.humanoid.WalkSpeed = 0

			local intro = ai.animations.StunIntro
			local loop = ai.animations.StunLoop
			local exit = ai.animations.StunExit

			intro:Play(0.15)

			intro.Ended:Once(function()
				loop:Play(0.15)

				task.delay(ai.config.StunDuration, function()
					exit:Play(0.15)
					loop:Stop(0.15)

					exit.Ended:Once(function()
						ai.flags.stunned = false
						ai.humanoid.WalkSpeed = ai.config.walkingSpeed
						ai.state:Change("Wander")
					end)
				end)
			end)
		end
	}
end

function States.BaseJumpscare(ai, options)
	options = options or {}

	local playEvent = options.playEvent
	local stopEvent = options.stopEvent
	local playerAnim = options.PlayerAnim
	local enemyAnim = options.EnemyAnim
	local impulse = options.Impulse or Vector3.new(0, 0, 0)

	return {
		Enter = function()
			if ai.flags.jumpscaring then return end
			ai.flags.jumpscaring = true

			local target = pathing.getNearestPlayer(ai.character, ai.config.HearingRange)
			if not target then return end

			local humanoid = ai.humanoid
			local root = ai.root
			local targetHumanoid = target:FindFirstChild("Humanoid")
			local targetRoot = target:FindFirstChild("HumanoidRootPart")

			humanoid.WalkSpeed = 0
			targetHumanoid.WalkSpeed = 0
			targetHumanoid.JumpPower = 0

			playEvent:FireClient(
				game.Players:GetPlayerFromCharacter(target),
				options.Type,
				root
			)

			local marker = root:FindFirstChild("JumpscarePlayerSpot")
			if marker then
				target:PivotTo(marker.CFrame)
			end

			ai.animations[enemyAnim]:Play(0.15)

			local pTrack = targetHumanoid.Animator:LoadAnimation(playerAnim)
			pTrack.Looped = false
			pTrack:Play(0.15)

			pTrack.Ended:Once(function()
				targetHumanoid.Health = 0
				targetHumanoid.PlatformStand = true
				stopEvent:FireClient(game.Players:GetPlayerFromCharacter(target), "Zombie")
				targetRoot:ApplyImpulse(impulse)
			end)

			ai.animations[enemyAnim].Ended:Once(function()
				ai.flags.jumpscaring = false
				ai.state:Change("Wander")
			end)
		end
	}
end




ZombieAI.__index = ZombieAI
setmetatable(ZombieAI, baseAI)

local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local events = replicatedStorage:WaitForChild("Events"):WaitForChild("Zombie")
local jumpscareEvents = replicatedStorage:WaitForChild("Events"):WaitForChild("Jumpscares")
local effectEvents = replicatedStorage:WaitForChild("Events"):WaitForChild("Effects")

export type ZombieConfig = {
	Damage : number,
	HearingRange : number,
	walkingSpeed : number,
	runningSpeed : number,
	HitCooldown : number,
	StunDuration : number
}


function ZombieAI.New(character : Model, debugging : boolean)
	local config : ZombieConfig = {
		Damage = 25,
		HearingRange = 60,
		walkingSpeed = 13,
		runningSpeed = 20,
		HitCooldown = 2,
		StunDuration = 3,
	}
	
	local ai = baseAI.new(character, config)
	setmetatable(ai, ZombieAI)

	local configuration = character:FindFirstChild("Configuration")
	ai.character = character
	ai.debugging = debugging
	ai.canMove = true
	ai.state = StateMachine.new("Wander")
	ai.lastSeenTime = 0
	ai.loseTargetDelay = 2
	ai.canHit = true
	ai.lastHitTime = 0
	ai.target = nil
	ai.finishedWander = false
	ai.moveConnection = nil
	ai.playingChaseTheme = false
	
	function ai:Attack()
		ai.lastAttackTime = os.clock()
		local targetHumanoid = ai.target:FindFirstChild("Humanoid")
		local targetHRP = ai.target:FindFirstChild("HumanoidRootPart")
		
		if targetHumanoid.Health - ai.config.Damage <= 0 then
			ai.state:Change("Jumpscare")
		else
			ai.target:FindFirstChild("Humanoid"):TakeDamage(ai.config.Damage)
			events.HitPlayer:FireClient(Players:GetPlayerFromCharacter(ai.target))
			ai.animations["Hit"]:Play()
		end
		
		
		
	end
	
	
	ai:RegisterAnimation("StunIntro", script.StunEnterAnim, false)
	ai:RegisterAnimation("StunLoop", script.StunLoopAnim, true)
	ai:RegisterAnimation("StunExit", script.StunExitAnim, false)
	ai:RegisterAnimation("Hit", script.HitAnim, false)

	ai:RegisterAnimation("Kill", script.KillAnim, false)

	
	
	ai.state:AddState("Wander", States.BaseWander(ai))
	ai.state:AddState("Chase", States.BaseChase(ai))
	
	ai.state:AddState("Stunned", States.BaseStun(ai))
	ai.state:AddState("Jumpscare", States.BaseJumpscare(ai, {
		Type = "Zombie",
		playEvent = jumpscareEvents.PlayJumpscare,
		stopEvent = jumpscareEvents.FinishedJumpscare,
		PlayerAnim = script.PlayerKillAnim,
		EnemyAnim = "Kill",
		Impulse = Vector3.new(-100, 0, 100)
	}))
	
	
	setmetatable(ai, ZombieAI)
	return ai
end


function ZombieAI:BeginPathing()
	local humanoid : Humanoid = self.character:WaitForChild("Humanoid")
	
	humanoid.WalkSpeed = self.config.walkingSpeed
	
	
	local last = os.clock()

	while task.wait() do
		local now = os.clock()
		local dt = now - last
		last = now

		self.state:Update(dt)
	end
	
	
end


--------------------------------------------
-- Event Handler
--------------------------------------------

function ZombieAI.InitializeEvents()
	-- cameraShaker is an external library used for camera shaking
	local cameraShaker = require(replicatedStorage:WaitForChild("CameraShaker"))
	local zombieChaseTheme = game:GetService("SoundService"):WaitForChild("ZombieChase")
	-- screenEffects is an external library used for screen effects such as vignette
	local screenEffects = require(replicatedStorage:WaitForChild("ScreenEffects"))

	local hitPlayer = replicatedStorage:WaitForChild("Events").Zombie.HitPlayer
	local chasePlayer = replicatedStorage:WaitForChild("Events").Zombie.ChasePlayer
	local stoppedChasingPlayer = replicatedStorage:WaitForChild("Events").Zombie.StoppedChasingPlayer
	local playJumpscare = replicatedStorage:WaitForChild("Events").Jumpscares.PlayJumpscare
	local finishedJumpscare = replicatedStorage:WaitForChild("Events").Jumpscares.FinishedJumpscare

	hitPlayer.OnClientEvent:Connect(function()
		local camShake = cameraShaker.new(Enum.RenderPriority.Camera.Value, function(shakeCf)
			workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * shakeCf
		end)

		camShake:Start()

		camShake:Shake(cameraShaker.Presets.ZombieHit)
	end)


	chasePlayer.OnClientEvent:Connect(function(zombieRoot, enemy)
		if enemy == "Zombie" then
			zombieChaseTheme:Play()
		end


		-- increase FOV
		local fovInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local tween = tweenService:Create(workspace.CurrentCamera, fovInfo, {FieldOfView = 90})
		tween:Play()

		-- make camera look at zombie

		if not zombieRoot then return end

		local character = game.Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChild("Humanoid")
		if not humanoid then return end

		-- save state
		local oldType = workspace.CurrentCamera.CameraType
		local oldSubject = workspace.CurrentCamera.CameraSubject

		workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable

		local startTime = os.clock()
		local duration = 0.65
		local smoothness = 6

		-- update every frame so position follows player
		local connection
		connection = game:GetService("RunService").RenderStepped:Connect(function(dt)
			local root = character:FindFirstChild("HumanoidRootPart")
			if not root then return end

			local camPos = root.Position + Vector3.new(0, 2, 0)
			local targetCFrame = CFrame.new(camPos, zombieRoot.Position)

			workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame:Lerp(
				targetCFrame,
				math.clamp(dt * smoothness, 0, 1)
			)

			local tween = tweenService:Create(workspace.CurrentCamera, fovInfo, {FieldOfView = 50})
			tween:Play()

			if os.clock() - startTime >= duration then
				connection:Disconnect()
				workspace.CurrentCamera.CameraType = oldType
				workspace.CurrentCamera.CameraSubject = humanoid

				local tween = tweenService:Create(workspace.CurrentCamera, fovInfo, {FieldOfView = 90})
				tween:Play()
			end
		end)


		-- add vignette

		screenEffects.addVignette(0.35)

	end)

	stoppedChasingPlayer.OnClientEvent:Connect(function()
		zombieChaseTheme:Stop()

		-- decrease FOV

		local tweenInfo = TweenInfo.new(1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		local tween = tweenService:Create(workspace.CurrentCamera, tweenInfo, {FieldOfView = 70})
		tween:Play()


		-- remove vignette

		screenEffects.removeVignette()
	end)

	playJumpscare.OnClientEvent:Connect(function(jumpscareName, enemyRoot)
		if jumpscareName == "Zombie" then
			workspace.CurrentCamera.CameraType = Enum.CameraType.Scriptable

			local startTime = os.clock()

			local connection
			connection = game:GetService("RunService").RenderStepped:Connect(function(dt)
				local root = game.Players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
				if not root then return end

				local camPos = root.Position + Vector3.new(0, 2, 0)
				local targetCFrame = CFrame.new(camPos, enemyRoot.Position)

				workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame:Lerp(
					targetCFrame,
					math.clamp(dt * 6, 0, 1)
				)


				if os.clock() - startTime >= 0.65 then
					connection:Disconnect()
				end
			end)
		end
	end)

	finishedJumpscare.OnClientEvent:Connect(function(jumpscareName)
		if jumpscareName == "Zombie" then
			workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end
	end)
end

return ZombieAI
