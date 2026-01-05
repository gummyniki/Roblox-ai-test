local module = {}
local events = game:GetService("ReplicatedStorage"):WaitForChild("Events"):WaitForChild("Effects")
local tweenService = game:GetService("TweenService")

module.addVignette = function(transparency)
	local gui = game.Players.LocalPlayer.PlayerGui
	local vignette = gui:WaitForChild("VignetteGui").Vignette
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tweenService:Create(vignette, info, {ImageTransparency = transparency}):Play()
	vignette.Visible = true
end
module.removeVignette = function()
	local gui = game.Players.LocalPlayer.PlayerGui
	local vignette = gui:WaitForChild("VignetteGui").Vignette
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	tweenService:Create(vignette, info, {ImageTransparency = 1}):Play()
	vignette.Visible = false
end

events.ApplyVignette.OnClientEvent:Connect(function(transparency)
	module.addVignette(transparency)
end)

events.RemoveVignette.OnClientEvent:Connect(function()
	module.removeVignette()
end)

function module.ImpactFrame(duration : number, targets : {Instance}, targetColors : {Color3})
	local impactFrameColorCorrection = game:GetService("Lighting"):WaitForChild("ImpactFrameColorCorrection")
	
	impactFrameColorCorrection.Enabled = true
	for i, target in targets do
		if target:IsA("Model") then
			for _, part in target:GetChildren() do
				local highlight = Instance.new("Highlight")
				highlight.Parent = part
				highlight.FillTransparency = 0
				highlight.OutlineTransparency = 1
				highlight.FillColor = targetColors[i]
			end
			
		elseif target:IsA("BasePart") then
			local highlight = Instance.new("Highlight")
			highlight.Parent = target
			highlight.FillColor = targetColors[i]
		else
			warn("Targets specified are not a part or model!")
			return
		end
	end
	
	task.wait(duration)
	
	for i, target in targets do
		if target:IsA("Model") then
			for _, part in target:GetChildren() do
				local highlight = part:FindFirstChildWhichIsA("Highlight")
				if highlight then
					highlight:Destroy()
				end
			end

		elseif target:IsA("BasePart") then
			local highlight = target:FindFirstChildWhichIsA("Highlight")
			
			if highlight then
				highlight:Destroy()
			end
		else
			warn("Targets specified are not a part or model!")
			return
		end
	end
	
	impactFrameColorCorrection.Enabled = false
end

return module
