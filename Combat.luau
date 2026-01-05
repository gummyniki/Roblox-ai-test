local Combat = {}
local raycastVisualizer = require(game.ReplicatedStorage.CastVisuals)

function Combat.RaycastHit(ai, range)
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

function Combat.BlockCastPart(part : BasePart, size : Vector3, offset : Vector3, params : RaycastParams, debugging : boolean)
	local baseParams = RaycastParams.new()
	baseParams.FilterType = Enum.RaycastFilterType.Exclude
	baseParams.FilterDescendantsInstances = {part}
	
	params = params or baseParams
	size = size or Vector3.new(1, 1, 1)
	offset = offset or Vector3.new(0, 0, 0)
	local blockcast = workspace:Blockcast(part.CFrame + offset, size, part.CFrame.LookVector, params)
	
	if debugging then
		local visualizer = raycastVisualizer.new(Color3.new(0.666667, 0, 0))
		visualizer:Blockcast(part.CFrame + offset, size, part.CFrame.LookVector, params)	
	end
	
	return blockcast
	
	
end

return Combat
