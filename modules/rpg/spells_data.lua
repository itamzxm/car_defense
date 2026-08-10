-- spells_data.lua
-- 魔法技能纯数据表（从 spells.lua 抽取）：spells 技能数据 / itam_spell 升级参数 / projectile_types 投射物类型
-- 供 spells.lua 引用；新增技能时在 [spells] 末尾追加即可

local Data = {}

local spells = {}
    spells[#spells + 1] = {
        name = {'entity-name.express-transport-belt'},
        entityName = 'express-transport-belt',
        level = 45,
        type = 'item',
        mana_cost = 150,
        tick = 300,
        enabled = true,
        sprite = 'recipe/express-transport-belt'
    }
    spells[#spells + 1] = {
        name = {'entity-name.express-underground-belt'},
        entityName = 'express-underground-belt',
        level = 40,
        type = 'item',
        mana_cost = 200,
        tick = 300,
        enabled = true,
        sprite = 'recipe/express-underground-belt'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-sand-rock'},
        entityName = 'big-sand-rock',
        level = 60,
        type = 'entity',
        mana_cost = 100,
        tick = 350,
        enabled = false,
        sprite = 'entity/big-sand-rock'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-biter'},
        entityName = 'small-biter',
        level = 10,
        biter = true,
        type = 'entity',
        mana_cost = 45,
        tick = 200,
        enabled = false,
        sprite = 'entity/small-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-spitter'},
        entityName = 'small-spitter',
        level = 10,
        biter = true,
        type = 'entity',
        mana_cost = 45,
        tick = 200,
        enabled = false,
        sprite = 'entity/small-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-biter'},
        entityName = 'medium-biter',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 75,
        tick = 300,
        enabled = false,
        sprite = 'entity/medium-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-spitter'},
        entityName = 'medium-spitter',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 75,
        tick = 300,
        enabled = false,
        sprite = 'entity/medium-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-biter'},
        entityName = 'big-biter',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 120,
        tick = 300,
        enabled = false,
        sprite = 'entity/big-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-spitter'},
        entityName = 'big-spitter',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 120,
        tick = 300,
        enabled = false,
        sprite = 'entity/big-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-biter'},
        entityName = 'behemoth-biter',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = false,
        sprite = 'entity/behemoth-biter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-spitter'},
        entityName = 'behemoth-spitter',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = false,
        sprite = 'entity/behemoth-spitter'
    }
    spells[#spells + 1] = {
        name = {'entity-name.small-worm-turret'},
        entityName = 'small-worm-turret',
        level = 35,
        biter = true,
        type = 'entity',
        mana_cost = 200,
        tick = 300,
        enabled = true,
        sprite = 'entity/small-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.medium-worm-turret'},
        entityName = 'medium-worm-turret',
        level = 50,
        biter = true,
        type = 'entity',
        mana_cost = 300,
        tick = 300,
        enabled = true,
        sprite = 'entity/medium-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.big-worm-turret'},
        entityName = 'big-worm-turret',
        level = 80,
        biter = true,
        type = 'entity',
        mana_cost = 450,
        tick = 300,
        enabled = true,
        sprite = 'entity/big-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.behemoth-worm-turret'},
        entityName = 'behemoth-worm-turret',
        level = 120,
        biter = true,
        type = 'entity',
        mana_cost = 700,
        tick = 300,
        enabled = true,
        sprite = 'entity/behemoth-worm-turret'
    }
    spells[#spells + 1] = {
        name = {'entity-name.biter-spawner'},
        entityName = 'biter-spawner',
        level = 90,
        biter = true,
        type = 'entity',
        mana_cost = 500,
        tick = 1420,
        enabled = true,
        sprite = 'entity/biter-spawner'
    }
    spells[#spells + 1] = {
        name = {'entity-name.spitter-spawner'},
        entityName = 'spitter-spawner',
        level = 90,
        biter = true,
        type = 'entity',
        mana_cost = 500,
        tick = 1420,
        enabled = true,
        sprite = 'entity/spitter-spawner'
    }

    spells[#spells + 1] = {
        name = {'item-name.slowdown-capsule'},
        entityName = 'slowdown-capsule',
        target = true,
        amount = 1,
        damage = true,
        force = 'player',
        level = 25,
        type = 'item',
        mana_cost = 175,
        tick = 150,
        enabled = true,
        sprite = 'recipe/slowdown-capsule'
    }
    spells[#spells + 1] = {
        name = {'item-name.grenade'},
        entityName = 'grenade',
        target = true,
        amount = 1,
        damage = true,
        force = 'player',
        level = 10,
        type = 'item',
        mana_cost = 50,
        tick = 50,
        enabled = true,
        sprite = 'recipe/grenade'
    }
    spells[#spells + 1] = {
        name = {'item-name.cluster-grenade'},
        entityName = 'cluster-grenade',
        target = true,
        amount = 2,
        damage = true,
        force = 'player',
        level = 30,
        type = 'item',
        mana_cost = 250,
        tick = 200,
        enabled = true,
        sprite = 'recipe/cluster-grenade'
    }
    spells[#spells + 1] = {
        name = {'spells.repair_aoe'},
        entityName = 'repair_aoe',
        target = true,
        amount = 1,
        range = 50,
        damage = false,
        force = 'player',
        level = 45,
        type = 'special',
        mana_cost = 150,
        tick = 100,
        enabled = true,
        sprite = 'recipe/repair-pack'
    }
    spells[#spells + 1] = {
        name = {'spells.raw_fish'},
        entityName = 'raw-fish',
        target = false,
        amount = 4,
        capsule = true,
        damage = false,
        range = 30,
        force = 'player',
        level = 10,
        type = 'special',
        mana_cost = 100,
        tick = 320,
        enabled = true,
        sprite = 'item/raw-fish'
    }

    spells[#spells + 1] = {
        name = {'spells.warp'},
        entityName = 'warp-gate',
        target = true,
        force = 'player',
        level = 45,
        type = 'special',
        mana_cost = 400,
        tick = 2000,
        enabled = true,
        sprite = 'virtual-signal/signal-W'
    }
    spells[#spells + 1] = {
        name = {'spells.wudi_turret'},
        itam_code=true,
        entityName = 'wudi_turret',
        insert='firearm-magazine',
        target = true,
        force = 'player',
        level = 35,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'recipe/gun-turret'
    }
    spells[#spells + 1] = {
        name = {'spells.biter_special_forces'},
        itam_code=true,
        entityName = 'biter_special_forces',
        target = true,
        force = 'player',
        level = 50,
        type = 'special',
        mana_cost = 250,
        tick = 100,
        enabled = true,
        sprite = 'item/submachine-gun'
    }

    spells[#spells + 1] = {
        name = {'spells.jgq'},
        itam_code=true,
        entityName = 'jgq',
        target = true,
        force = 'player',
        level = 15,
        type = 'special',
        mana_cost = 100,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-B'
    }
    spells[#spells + 1] = {
        name = {'spells.ufo'},
        itam_code=true,
        entityName = 'ufo',
        target = true,
        force = 'player',
        level = 100,
        type = 'special',
        mana_cost = 750,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-C'
    }
    spells[#spells + 1] = {
        name = {'spells.lightning_chain'},
        itam_code=true,
        entityName = 'lightning_chain',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-L'
    }
    spells[#spells + 1] = {
        name = {'spells.jx'},
        itam_code=true,
        entityName = 'jx',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 350,
        tick = 100,
        enabled = true,
        sprite = 'item/exoskeleton-equipment'
    }
    spells[#spells + 1] = {
        name = {'spells.lyly'},
        itam_code=true,
        entityName = 'lyly',
        target = true,
        force = 'player',
        level = 35,
        type = 'special',
        mana_cost = 75,
        tick = 100,
        enabled = false,
        sprite = 'item/flamethrower-ammo'
    }
    spells[#spells + 1] = {
        name = {'spells.ssz'},
        itam_code=true,
        entityName = 'ssz',
        target = true,
        force = 'player',
        level = 30,
        type = 'special',
        mana_cost = 200,
        tick = 100,
        enabled = true,
        sprite = 'recipe/stone-wall'
    }
    spells[#spells + 1] = {
        name = {'spells.distractor'},
        entityName = 'distractor-capsule',
        target = true,
        amount = 1,
        damage = false,
        range = 30,
        force = 'player',
        level = 25,
        type = 'special',
        mana_cost = 125,
        tick = 320,
        enabled = true,
        sprite = 'recipe/distractor-capsule'
    }
    spells[#spells + 1] = {
        name = {'item-name.atomic-bomb'},
        entityName = 'atomic-bomb',
        range = 64,
        target = true,
        amount = 1,
        damage = true,
        force = 'enemy',
        level = 120,
        type = 'item',
        mana_cost = 1000,
        tick = 1500,
        enabled = true,
        sprite = 'recipe/atomic-bomb'
    }
    spells[#spells + 1] = {
        name = {'spells.ch'},
        itam_code = true,
        entityName = 'ch',
        target = true,
        force = 'player',
        level = 60,
        type = 'special',
        mana_cost = 800,
        tick = 100,
        enabled = true,
        sprite = 'entity/biter-spawner'
    }
    spells[#spells + 1] = {
        name = {'spells.huo_dun'},
        itam_code = true,
        entityName = 'huo_dun',
        target = true,
        force = 'player',
        level = 40,
        type = 'special',
        mana_cost = 250,
        tick = 100,
        enabled = true,
        sprite = 'item/flamethrower-ammo'
    }
    spells[#spells + 1] = {
        name = {'spells.advanced_fishing'},
        itam_code = true,
        entityName = 'advanced_fishing',
        target = false,
        force = 'player',
        level = 20,
        type = 'special',
        mana_cost = 80,
        tick = 320,
        enabled = true,
        sprite = 'item/raw-fish'
    }
    spells[#spells + 1] = {
        name = {'spells.shui_long_dan'},
        itam_code = true,
        entityName = 'shui_long_dan',
        target = true,
        force = 'player',
        level = 50,
        type = 'special',
        mana_cost = 300,
        tick = 100,
        enabled = true,
        sprite = 'item/offshore-pump'
    }
    spells[#spells + 1] = {
        name = {'spells.huanxing_huoshan_penfa'},
        itam_code = true,
        entityName = 'huanxing_huoshan_penfa',
        target = true,
        force = 'player',
        level = 70,
        type = 'special',
        mana_cost = 500,
        tick = 100,
        enabled = true,
        sprite = 'entity/small-demolisher-fissure'
    }
    spells[#spells + 1] = {
        name = {'spells.leizhenyu'},
        itam_code = true,
        entityName = 'leizhenyu',
        target = true,
        force = 'player',
        level = 60,
        type = 'special',
        mana_cost = 350,
        tick = 100,
        enabled = true,
        sprite = 'entity/lightning'
    }
    spells[#spells + 1] = {
        name = {'spells.diankuang'},
        itam_code = true,
        entityName = 'diankuang',
        target = true,
        force = 'player',
        level = 90,
        type = 'special',
        mana_cost = 600,
        tick = 100,
        enabled = true,
        sprite = 'virtual-signal/signal-Z'
    }
    spells[#spells + 1] = {
        name = {'spells.bullet_supply_tower'},
        itam_code = true,
        entityName = 'bullet_supply_tower',
        target = true,
        force = 'player',
        level = 10,
        type = 'special',
        mana_cost = 100,
        tick = 100,
        enabled = true,
        sprite = 'entity/passive-provider-chest'
    }


Data.spells = spells

Data.itam_spell = {
    ['wudi_turret'] = {max_range = 36, tick_speed = 1, need_list = {1, 200, 1000}, upgrade_list = {'firearm-magazine', 'piercing-rounds-magazine', 'uranium-rounds-magazine'}},
    ['biter_special_forces'] = {max_range = 36, tick_speed = 1, need_list = {1, 300, 500, 1000}, upgrade_list = {'1', '2', '3', '4'}},
    ['ch'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['ssz'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['jx'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['lyly'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['jgq'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['ufo'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['lightning_chain'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['leizhenyu'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['huo_dun'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['shui_long_dan'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['advanced_fishing'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['yjjn'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['huanxing_huoshan_penfa'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['diankuang'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
    ['bullet_supply_tower'] = {max_range = 36, tick_speed = 1, need_times = 50, bonus = 1, base = 1},
}

Data.projectile_types = {
    ['distractor-capsule'] = {name = 'distractor-capsule', count = 1, max_range = 36, tick_speed = 1},
    ['grenade'] = {name = 'grenade', count = 1, max_range = 36, tick_speed = 1},
    ['cluster-grenade'] = {name = 'cluster-grenade', count = 1, max_range = 36, tick_speed = 1},
    ['slowdown-capsule'] = {name = 'slowdown-capsule', count = 1, max_range = 36, tick_speed = 1},
    ['atomic-bomb'] = {name = 'atomic-bomb', count = 1, max_range = 36, tick_speed = 1},
    ['warp-gate'] = {name = 'warp-gate', count = 1, max_range = 36, tick_speed = 1},
}

return Data
