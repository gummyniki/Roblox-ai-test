local replicatedStorage = game:GetService("ReplicatedStorage")
local pathing = require(replicatedStorage.Pathing)
local combat = require(replicatedStorage.Combat)

local States = {}


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


return States
