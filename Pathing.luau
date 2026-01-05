local PathfindingService = game:GetService("PathfindingService")

local Pathing = {}

function Pathing.FollowTarget(ai, destination)
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


function Pathing.hasLineOfSight(from, to, targetCharacter, ignore)
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


function Pathing.getNearestPlayer(character: Model, maxRange: number)
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


function Pathing.moveToRandomPoint(ai, debugging: boolean)
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

return Pathing
