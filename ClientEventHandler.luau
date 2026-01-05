local ReplicatedStorage = game:GetService("ReplicatedStorage")
local cameraShaker = require(ReplicatedStorage:WaitForChild("CameraShaker"))
local zombieChaseTheme = game:GetService("SoundService"):WaitForChild("ZombieChase")
local screenEffects = require(ReplicatedStorage:WaitForChild("ScreenEffects"))
local tweenService = game:GetService("TweenService")

local hitPlayer = ReplicatedStorage:WaitForChild("Events").Zombie.HitPlayer
local chasePlayer = ReplicatedStorage:WaitForChild("Events").Zombie.ChasePlayer
local stoppedChasingPlayer = ReplicatedStorage:WaitForChild("Events").Zombie.StoppedChasingPlayer
local playJumpscare = ReplicatedStorage:WaitForChild("Events").Jumpscares.PlayJumpscare
local finishedJumpscare = ReplicatedStorage:WaitForChild("Events").Jumpscares.FinishedJumpscare

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