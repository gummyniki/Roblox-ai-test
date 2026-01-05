local BaseAI = {}
BaseAI.__index = BaseAI

function BaseAI.new(character, config)
	local self = setmetatable({}, BaseAI)

	self.character = character
	self.humanoid = character:WaitForChild("Humanoid")
	self.root = character:WaitForChild("HumanoidRootPart")
	self.animator = self.humanoid:FindFirstChild("Animator")

	self.state = require(game.ReplicatedStorage.StateMachine).new("Idle")

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

function BaseAI:CanAttack()
	return os.clock() - self.lastAttackTime >= self.config.HitCooldown
end

function BaseAI:Attack()
	self.lastAttackTime = os.clock()
end

function BaseAI:SetTarget(target)
	self.target = target
end

function BaseAI:ClearTarget()
	self.target = nil
end

function BaseAI:Update(dt)
	self.state:Update(dt)
end

function BaseAI:StopMovement()
	if self.moveConnection then
		self.moveConnection:Disconnect()
		self.moveConnection = nil
	end

	self.humanoid:Move(Vector3.zero)
end

function BaseAI:RegisterAnimation(name, animation, looped)
	local track = self.animator:LoadAnimation(animation)
	track.Looped = looped
	self.animations[name] = track
	return track
end

function BaseAI:InitCooldowns()
	self.cooldowns = {}
end

function BaseAI:SetCooldown(name, duration)
	self.cooldowns[name] = os.clock() + duration
end

function BaseAI:IsOnCooldown(name)
	local t = self.cooldowns[name]
	return t ~= nil and os.clock() < t
end

function BaseAI:ClearCooldown(name)
	self.cooldowns[name] = nil
end


return BaseAI
