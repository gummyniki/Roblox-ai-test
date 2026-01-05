local baseAI = require(game:GetService("ReplicatedStorage").BaseAI)


local ZombieAI = {}
ZombieAI.__index = ZombieAI
setmetatable(ZombieAI, baseAI)

local Players = game:GetService("Players")
local replicatedStorage = game:GetService("ReplicatedStorage")
local StateMachine  = require(replicatedStorage:WaitForChild("StateMachine"))

local States = require(replicatedStorage.BaseStates)
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

return ZombieAI
