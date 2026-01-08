--[[
	Zombie AI
	---------
	Features:
		- Wander / Chase / Jumpscare states
		- Custom State Machine for zombie behavior
		- Hearing / Seeing system using magnitude and raycasting
		- Chase Music
		- Fully Modularized
]]



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

-- StateMachine
-- Simple state machine with enter/update/exit loops
-- Supports hard-locks (e.g. jumpscare) to prevent invalid state transitions
StateMachine.__index = StateMachine

-- Simple metatable creation for the state machine
function StateMachine.new(initialState, selfAI)
	return setmetatable({
		current = initialState,
		ai = selfAI,
		previous = nil,
		states = {}
	}, StateMachine)
end

-- Adds a state to the state machine
function StateMachine:AddState(name, state)
	self.states[name] = state
end

-- Simply returns the current state property
function StateMachine:Get()
	return self.current
end

-- Handles changing between states
-- Makes sure to exit the old state and enter the new one as to not cause logic issues
-- Has a hard lock for jumpscaring
function StateMachine:Change(newState)
	if self.ai.flags.jumpscaring and newState ~= "Jumpscare" then
		return
	end
	
	if self.current == newState then return end

	local oldState = self.current
	self.previous = oldState

	if oldState and self.states[oldState] and self.states[oldState].Exit then
		self.states[oldState].Exit()
	end

	self.current = newState

	if self.states[newState] and self.states[newState].Enter then
		self.states[newState].Enter()
	end
end

-- Forwards dt to the current state's update loop
function StateMachine:Update(dt)
	local state = self.states[self.current]
	if state and state.Update then
		state.Update(dt)
	end
end

---------------------------------------------
-- Pathing
--------------------------------------------

-- Helper function for following a specified target using pathfinding
-- It handles character jumping, as well as recalculating pathfinding every time the ai moves a bit as to always be chasing the current target position
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

-- Helper function to check if the ai can see the target using raycasting
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

-- Runs a magnitude check on every player to check if one is close enough to the ai
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

-- Moves the ai to a random position in an 100 stud radius using pathfinding
-- Makes sure only one move connection is active at a time as to not cause logic issues
-- Only works in the wander state
-- Has optional path debugging
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

-- Casts a ray in front of the ai with the specified range and returns the result
function combat.RaycastHit(ai, range)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ai.character }

	local result = workspace:Raycast(ai.root.Position, ai.root.CFrame.LookVector * range, params)
	

	return result
end

---------------------------------------------
-- Base AI
---------------------------------------------

-- BaseAI
-- Handles Core AI mechanics such as state machine creation and animations
-- Most functions should be self explanatory

baseAI.__index = baseAI

function baseAI.new(character, config)
	local self = setmetatable({}, baseAI)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")
	self.animator = self.humanoid:FindFirstChild("Animator")

	self.state = StateMachine.new("Idle", self)

	self.config = config
	self.target = nil

	self.lastAttackTime = 0
	self.isWandering = false

	self.animations = {}
	self.flags = {
		stunned = false,
		jumpscaring = false
	}
	
	self.state.ai = self

	return self
end

function baseAI:CanAttack()
	return os.clock() - self.lastAttackTime >= self.config.HitCooldown
end

-- Overriden later
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

-- Disconnects the ai's move connection if it exists and cancells any MoveTo function
function baseAI:StopMovement()
	if self.moveConnection then
		self.moveConnection:Disconnect()
		self.moveConnection = nil
	end

	self.humanoid:Move(Vector3.zero)
end

-- Loads an animation object into the ai using it's humanoid and saves it into a dictionary
function baseAI:RegisterAnimation(name, animation, looped)
	local track = self.animator:LoadAnimation(animation)
	track.Looped = looped
	self.animations[name] = track
	return track
end

------------------------------------------------
-- Zombie States
------------------------------------------------

-- States
-- Handles actual zombie logic
-- Uses Enter(), Update() and Exit() functions

-- Wander state
-- Makes sure the ai can move and isn't jumpscaring, as well as cancelling any move connection
-- Uses the earlier defined Pathing helpers
-- Checks for players inside it's hearing radius and makes sure the zombie can see them
-- If it finds a player then it changes to the Chase state
function States.BaseWander(ai, options)
	options = options or {}

	return {
		Enter = function()
			if ai.flags.jumpscaring then return end
			if not ai.canMove then return end
			ai.humanoid.WalkSpeed = ai.config.walkingSpeed
			
			ai.isWandering = false
			ai.finishedWander = false

			if ai.moveConnection then
				ai.moveConnection:Disconnect()
				ai.moveConnection = nil
			end
			
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

-- Chase state
-- Handles chasing the nearest player using the Pathing helper
-- Fires client events for effects like vignette, fov change and chase music
-- If close enough to the player, calls the ai's Attack() method
-- If it loses the player, it transitions back to the wander state
function States.BaseChase(ai, options)
	options = options or {}
	local enemy = options.Enemy or "Zombie"
	local attackRange = options.AttackRange or 2
	local chasePlayerEvent = options.chasePlayerEvent or game.ReplicatedStorage.Events.Zombie.ChasePlayer
	local stoppedChasePlayerEvent = options.StoppedChasePlayerEvent or game.ReplicatedStorage.Events.Zombie.StoppedChasingPlayer

	return {
		Enter = function()
			if not ai.canMove then return end
			if ai.flags.jumpscaring then return end 
			ai.humanoid.WalkSpeed = ai.config.runningSpeed
			chasePlayerEvent:FireClient(game.Players:GetPlayerFromCharacter(ai.target), ai.root, enemy)
		end,	

		Update = function(dt)
			if ai.flags.jumpscaring then return end
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
			local target = ai.target
			
			if not target then
				ai.state:Change("Wander")
				return
			end

			local targetRoot = target:FindFirstChild("HumanoidRootPart")
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
				local player = game.Players:GetPlayerFromCharacter(target)
				if player then
					stoppedChasePlayerEvent:FireClient(player)
				end

			end
		end

	}

end


-- Jumpscare state
-- Handles freezing the ai and player in place and playing their specified kill animations
-- Turns on the state machine's hard lock as to make sure the jumpscare isn't cancelled

function States.BaseJumpscare(ai, options)
	options = options or {}

	local playEvent = options.playEvent
	local stopEvent = options.stopEvent
	local playerAnim = options.PlayerAnim
	local enemyAnim = options.EnemyAnim
	local impulse = options.Impulse or Vector3.new(0, 0, 0)

	return {
		Enter = function()
			ai.canMove = false
			ai:StopMovement()
			
			local root = ai.root

			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root:SetNetworkOwner(nil)


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
				ai.target = nil
				ai.canMove = true
				root.Anchored = false
				root:SetNetworkOwner(nil)
				
				task.wait(0.5)
				ai.state:Change("Wander")
			end)
		end,
		
		Exit = function()
			ai.flags.jumpscaring = false
			ai.canMove = true
			ai:StopMovement()
		end,

	}
end


-- ZombieAI
-- The actual ai creation
-- Inherits from BaseAI
-- Adds the required states and overrides the original ai:Attack()

ZombieAI.__index = ZombieAI
setmetatable(ZombieAI, baseAI)

local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local events = replicatedStorage:WaitForChild("Events"):WaitForChild("Zombie")
local jumpscareEvents = replicatedStorage:WaitForChild("Events"):WaitForChild("Jumpscares")
local effectEvents = replicatedStorage:WaitForChild("Events"):WaitForChild("Effects")

-- Custom type for the zombie configuration
export type ZombieConfig = {
	Damage : number,
	HearingRange : number,
	walkingSpeed : number,
	runningSpeed : number,
	HitCooldown : number,
	StunDuration : number
}

-- ZombieAI constructor
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
	ai.state = StateMachine.new("Wander", ai)
	ai.lastSeenTime = 0
	ai.loseTargetDelay = 2
	ai.canHit = true
	ai.lastHitTime = 0
	ai.target = nil
	ai.finishedWander = false
	ai.moveConnection = nil
	ai.playingChaseTheme = false
	
	-- Custom attack function for the zombie
	-- Handles damaging the player and changing to the jumpscare state if the hit is lethal
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

-- Starts the zombie ai by calling the state machine's Update() method uisng deltatime
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

--[[
	InitializeEvents
	- Must be called on the client
	- Initializes all remote events required for the zombie
	- Handles client effects like screen shaking, vignette, fov change and chase music
]]

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
