-- 天赋品质系统 helper（方案 D）
-- 无状态：品质只存于 global（this.skill 字典，键=技能名 值=品质整数 1..5），此处仅查表 + UI 派生。
-- 不缓存任何运行时状态到模块级 local，避免 desync（见项目记忆 utils/gui.lua 红线）。

local WPT = require 'maps.amap.table'
local pet = require 'modules.pet_system.table'
local Public = {}

-- 品质档位（整数 1..5 对应）
local NAMES = {'普通', '精良', '稀有', '史诗', '传说'}
local QUALITY_SPRITES = {
    'quality/normal',
    'quality/uncommon',
    'quality/rare',
    'quality/epic',
    'quality/legendary'
}

-- 品质系数（与三个 skill 文件保持一致；LOW=低基础值天赋，REG=常规天赋）
local COEFF_LOW = {1, 1.2, 1.4, 1.6, 1.8}
local COEFF_REG = {1, 1.2, 1.4, 1.6, 1.8}

-- 取整：直接 math.floor，严格对齐游戏内（应用代码与描述注入共用本函数，保证二者数值一致）
local function qround(x)
    return math.floor(x)
end

-- 限 2 位小数并去掉尾随零（用于「基准值本身为小数」的天赋：按用户规则不取整，只限制显示精度）
local function fmt2(x)
    local s = string.format('%.2f', x)
    s = s:gsub('%.?0+$', '')
    return s
end

-- 数值类天赋描述展示表：vals 为描述里随品质缩放的基准数字（普通档=q=1 即 vals×COEFF[1]）
-- coeff: 'LOW' 或 'REG'，对应上面两套系数。没有登记的天赋只显示品质名（向后兼容）。
local DISPLAY = {
    mlst = { coeff = 'LOW', vals = {1, 5} },  -- 每分钟活力 1~5，按品质缩放
    rsrl = { mult = 'LOW' },  -- 肉身熔炉：冶炼量=max(力量,敏捷)×品质系数(普通=基准,传说1.8×)
    shoucuo_de_shen = { arr = {1, 2, 3, 4, 5} },  -- 手搓的神：品质作用于额外获得数量 1/2/3/4/5
    -- 第一批（once 类，明确缩放）
    hc = { coeff = 'LOW', vals = {5} },                                                    -- 汽车等级 +5
    rich_son = { coeff = 'REG', vals = {7000} },                                           -- 金币 7000
    rs = { coeff = 'REG', vals = {80} },                                                   -- 活力 80
    tsxf = { coeff = 'REG', vals = {4000} },                                               -- 经验 4000
    bulider = { vals = { {v = 15, c = 'REG'}, {v = 1, c = 'LOW'}, {v = 10, c = 'LOW'} } }, -- 敏捷/手速/背包
    chishang = { coeff = 'REG', vals = {3000} },                                           -- 金币 3000
    quanneng = { coeff = 'REG', vals = {15} },                                             -- 全属性 15
    -- 第二批 B2（time 类，固定基准可写真实数字）
    cjs = { vals = { {v = 3, c = 'LOW'}, {v = 30, c = 'REG'}, {v = 1, c = 'LOW'} } },       -- 其他+3魔力LOW / 自己+30经验REG / 全能神全体+1魔力LOW
    whea = { coeff = 'LOW', vals = {5} },                                                  -- 每50虫 +5活力
    kytd = { arr = {1, 1, 2, 2, 3} },                                                      -- 每敏捷为主玩家 +1 敏捷(11223)
    dcrg = { coeff = 'REG', vals = {480} },                                                -- 满电激光伤害 480
    -- 第1组新增（重置后真实数字改造）
    shit_luck = { arr = {2, 3, 4, 5, 6} },                                                -- 抽奖次数 2~6（显式逐档，原2-4随机）
    xuetu = { coeff = 'LOW', vals = {1.5} },                                              -- 手搓经验 ×1.5（小数基准，不取整仅限2位）
    jiansheche = { arr = {250, 200, 167, 143, 125} },                                     -- 每X敏捷+6建筑（阈值=200/REG[q]）
    -- 第2组新增
    dianjiqiang = { coeff = 'REG', vals = {15} },                                          -- 电击枪基础伤害 15×REG
    wanlaotianlei = { coeff = 'REG', vals = {20} },                                        -- 万牢天雷引基础伤害 20×REG（额外+自身魔力，品质作用于魔法伤害）
    danmu_gongji = { coeff = 'LOW', vals = {8} },                                           -- 弹幕投掷数 8×LOW
    chongfengxianzhen = { arr = {1, 1, 2, 2, 3} },                                         -- 冲锋活力 +1(11223)
    bujiwu = { coeff = 'REG', vals = {5, 5} },                                              -- 布吉舞 收取/每150敏 +5 均×REG
    mzqz = { vals = { {v = 0.5, c = 'LOW'}, {v = 2, c = 'LOW'} } },                         -- 魔杖窃贼 经验0.5×/法力2× LOW（0.5小数不取整）
    -- 第3组新增
    zhrm = { coeff = 'REG', vals = {50} },                                                 -- 最大法力50%经验 → 40/50/60/70/80%
    kejigongsi = { coeff = 'REG', vals = {3.5} },                                          -- 科技3.5倍金币（小数，限2位）
    mbz = { mult = 'REG' },                                                                -- 敏捷=(等级*2+10)×REG
    tls = { arr = {1, 1, 2, 2, 3} },                                                      -- 每35级多召唤+1次(11223)
    zsfs = { coeff = 'REG', vals = {5} },                                                  -- 偷取5%金币 REG
    djrc = { arr = {1, 1, 2, 2, 3} },                                                      -- 每小时学习{1,1,2,2,3}个
    pulu = { coeff = 'REG', vals = {20} },                                                 -- 铺路宽20×REG
    scmcc = { coeff = 'REG', vals = {400} },                                               -- 铁矿基准400×REG
    -- 第4组新增
    dafs = { arr = {1, 1, 2, 2, 3} },                                                      -- 每友方虫1经验(11223)
    ljss = { arr = {1, 1, 2, 2, 3} },                                                      -- 每杀1经验/每125魔+1 均11223
    ylsgd = { coeff = 'LOW', vals = {6, 3} },                                              -- 6建筑/每200敏+3 均LOW
    tann = { coeff = 'REG', vals = {3, 1} },                                               -- 偷3%/每100敏+1% 均REG
    xly = { coeff = 'REG', vals = {100, 100} },                                            -- 分发100经验/每10级+100 均REG
    tzzj = { coeff = 'REG', vals = {5} },                                                  -- 资产+5% REG
    -- 第5组新增
    xj = { coeff = 'LOW', vals = {20} },                                                    -- 已损失生命20%伤害 LOW
    jndd = { arr = {1, 1, 2, 2, 3} },                                                    -- 低初始值11223，仅缩放「每100敏捷金币系数」K
    ycj = { coeff = 'REG', vals = {60, 10} },                                              -- 60金/每100敏+10 均REG
    falibiqu = { coeff = 'REG', vals = {10, 2} },                                          -- 伤害10+法力2% 均REG
    dl = { coeff = 'LOW', vals = {1.5} },                                                  -- 移速1.5倍 LOW（小数限2位）
    jifengbu = { coeff = 'LOW', vals = {10, 10} },                                         -- 移速10%/每100法+10% 均LOW
    jxhx = { coeff = 'REG', vals = {2500} },                                               -- 充电2500 REG
    -- 第6组新增
    xxzb = { arr = {1, 1, 2, 2, 3} },                                                     -- 每秒/每400活力 +1法力(11223)
    xuyiyiquan = { coeff = 'REG', vals = {40} },
    juemuren = { coeff = 'LOW', vals = {20} },
    lg = { arr = {1, 1, 2, 2, 3} },                                                       -- 每100尸体 +1力量(11223)
    xxg = { arr = {1, 1, 2, 2, 3} },                                                      -- 每100尸体 +1活力(11223)
    chifu = { arr = {2, 2, 3, 3, 4} },                                              -- 治疗2%×LOW→四舍五入
    touqian = { coeff = 'REG', vals = {30} },
    -- 第7组新增
    sglz = { coeff = 'LOW', vals = {15, 10} },
    bpz = { arr = {1, 1, 2, 2, 3} },
    small_buss = { coeff = 'REG', vals = {10} },
    zrsc = { arr = {3, 4, 4, 5, 5} },                                              -- 活力+3×LOW→四舍五入
    zhs = { arr = {1, 1, 2, 2, 3} },
    -- 第8组新增
    wolf = { coeff = 'LOW', vals = {20} },
    wxs = { coeff = 'LOW', vals = {5} },
    fish = { arr = {1, 1, 2, 2, 3} },                                                     -- 每200魔法 +1鱼(11223)
    hd = { coeff = 'REG', vals = {5} },
    fali = { coeff = 'LOW', vals = {5} },
    juqichengjian = { mult = 'REG' },
    -- 第9组新增
    carxiu = { coeff = 'LOW', vals = {5} },        -- 修车 5%×LOW
    ftlt = { coeff = 'REG', vals = {100} },        -- 铁/铜板 100×REG
    tdlx = { coeff = 'LOW', vals = {5} },          -- 每人 5 经验×LOW
    dianluban = { coeff = 'REG', vals = {6, 18} }, -- 铁板6/铜线18 均×REG
    xueqiu = { arr = {2, 2, 3, 3, 4} },        -- 经验+2×LOW→四舍五入
    pailei = { coeff = 'REG', vals = {500} },      -- 每雷 500 金币×REG
    xxyd = { coeff = 'LOW', vals = {1, 5} },       -- 每分钟魔力 1~5×LOW（同 mlst）
    -- 第10组新增
    morefali = { coeff = 'LOW', vals = {30} },        -- 回蓝 30%×LOW
    shen_fa = { coeff = 'REG', vals = {20, 5} },      -- 总额20/每点魔力+5 均×REG
    zishenzhuanjia = { coeff = 'REG', vals = {10} },  -- 触发率 10%×REG
    hushenfu = { coeff = 'LOW', vals = {10} },        -- 治疗 10%×LOW
    zhuoshao = { coeff = 'REG', vals = {15, 4} },     -- 基础15/每级+4 均×REG
    shui_hu_fu = { arr = {1, 1, 2, 2, 3} },          -- 每30秒充能层数
    -- 第11组新增
    chaoshikongshangdian = { arr = {20, 16, 12, 8, 4} },  -- 原价折扣%(逆方向:品质越高越便宜)
    yelianche = { coeff = 'REG', vals = {50} },           -- 冶炼量=敏捷50%×REG
    tianzhao = { arr = {1, 2, 3, 4, 5} },                -- 点燃目标数
    yuedui_gushou = { coeff = 'REG', vals = {20} },       -- 半径20×REG
    tesla_battery = { coeff = 'REG', vals = {10} },       -- 满充能金币=敏捷10%×REG
    lidazhuanfei = { coeff = 'REG', vals = {20} },        -- 力量20%伤害×REG
    ailunisi = { arr = {1.5, 2.0, 2.5, 3.0, 3.5} },      -- 周期伤害倍率
    haiguanfang = { arr = {1, 2, 3, 4, 5} },             -- 鱼数
    mijingzhang = { mult = 'REG' },                    -- 魔晶杖：基准伤害公式 × REG
    -- 第12组新增
    gongshengti = { coeff = 'LOW', vals = {50} },       -- 共生体 效率50%×LOW
    wuqidashi = { coeff = 'LOW', vals = {20} },         -- 电磁专家 激光伤害+20%×LOW
    shengguangzhongji = { coeff = 'LOW', vals = {1, 2} }, -- 圣光重击 治疗1%/伤害2% 均×LOW
    -- 第13组新增
    yinxuejian = { coeff = 'LOW', vals = {20} },          -- 饮血剑 回血20%力×LOW
    smmf = { arr = {4, 5, 6, 6, 7} },                 -- 魔法盾 1:4×LOW 四舍五入取整
    tjjz = { arr = {1, 1, 2, 2, 3} },                    -- 痛苦教教主 四维+{1,1,2,2,3}
    relife = { arr = {6, 7, 8, 9, 10} },               -- 重生 无敌6秒×REG
    sxf = { coeff = 'REG', vals = {30} },                 -- 失心疯 +30敏×REG
    -- 第14组新增
    kxj = { vals = { {v = 2, c = 'LOW'}, {v = 50, c = 'REG'} } }, -- 疯狂科学家 +2敏LOW / +50金币REG
    baot = { coeff = 'REG', vals = {25} },                 -- 暴徒 力量25%伤害×REG
    willdie = { arr = {8, 9, 10, 11, 12} },               -- 时间回溯 安全8秒×REG
    liliangup = { arr = {1, 1, 2, 2, 3} },                 -- 力量训练 +{1,1,2,2,3}力
    -- 第15组新增
    fcz = { arr = {2, 2, 3, 3, 4} },                    -- 复仇者 全属性+2×LOW→四舍五入
    jiantazhe = { coeff = 'REG', vals = {20} },             -- 践踏者 力量20%伤害×REG
    xixue = { arr = {1, 1, 2, 2, 3} },                      -- 蠕虫 属性+{1,1,2,2,3}
    zg = { arr = {1, 1, 2, 2, 3} },                         -- 宰割 金币{1,1,2,2,3}
    sgj = { arr = {1, 1, 2, 2, 3} },                        -- 收割机 力量+{1,1,2,2,3}
    sangjin = { coeff = 'REG', vals = {250} },               -- 赏金猎人 250金币×REG
    dgjx = { coeff = 'REG', vals = {5} },                   -- 帝国军饷 5金币×REG
    -- 第16组新增
    htms = { coeff = 'REG', vals = {500, 300} },             -- 红图抹杀 总伤害(500+法力*300)×REG
    shouyiren = { coeff = 'REG', vals = {5} },               -- 手艺人 5金币×REG
    dingjilueshizhe = { arr = {1, 1, 2, 2, 3} },             -- 顶级掠食者 力/活+{1,1,2,2,3}
    peishentuanyuan = { arr = {1, 1, 2, 2, 3} },             -- 陪审团 力量+{1,1,2,2,3}
    shencizhishou = { arr = {16, 17, 18, 19, 20} },     -- 神赐之手 持续16/17/18/19/20秒
    -- 第17组新增
    fengyinjuanzhou = { coeff = 'LOW', vals = {10} },         -- 封印卷轴 法力+10×LOW
    dijiaojiaotu = { coeff = 'LOW', vals = {2, 5} },           -- 低级教徒 法力2/经验5×LOW
    pochen_bawangqiang = { vals = { {v = 50, c = 'REG'}, {v = 25, c = 'REG'}, {v = 10, c = 'LOW'} } }, -- 破阵霸王枪 力50%×REG/血25%×REG/伤+10×LOW
    shimozhe = { arr = {1, 1, 2, 2, 3} },                            -- 噬魔者 法力+{1,1,2,2,3}
    yl = { arr = {1, 2, 3, 4, 5} },                              -- 鱼灵 攻击目标数
    yanmo = { mult = 'REG' },                                  -- 炎魔 伤害×REG
    leitingwanjun = { mult = 'REG' },                       -- 雷霆万钧 伤害×REG
    smlw = { mult = 'REG' },                                  -- 神秘礼物 抽奖力度×REG
    chuanqibaozang = {},  -- 传说宝藏：品质仅作用于"保底产出品质"（__1__），数量倍率已移除
    diyu_rongyan = { mult = "REG" },
    dutu = { mult = "REG" },
    emengyingrao = { mult = "REG" },
    fuzhushou = { mult = "LOW" },
    gycs = { mult = "REG" },
    hkzy = { mult = "REG" },
    jgq = { mult = "REG" },
    jidiche = { mult = "REG" },
    jika = { mult = "REG" },
    kls = { mult = "REG" },
    mlzq = { mult = "LOW" },
    qykj = { mult = "REG" },
    shandianwulianbian = { mult = "REG" },
    shuangrenjian = { mult = "REG" },
    shui_dun = { mult = "REG" },
    tianshi = { mult = "REG" },
    tuks = { arr = {1, 1, 2, 2, 3} },
    wudi = { mult = "REG" },
    wuxingjue = { mult = "REG" },
    xuebao = { mult = "REG" },
    xueshu = { mult = "REG" },
    xybg = { mult = "LOW" },
    yanshu = { arr = {0.1, 0.2, 0.3, 0.4, 0.5} },
    yfz = { mult = "REG" },
    youxia = { arr = {1, 1, 2, 2, 3} },
    yubaobao = { mult = "LOW" },
    zhaohuan_kongxi = { mult = "REG" },
    zhiming = { mult = "REG" },
    shalujingyan = { mult = "LOW" },
    guajichengsheng = { coeff = 'REG', vals = {300} },  -- 挂机成圣：每分钟金币 300×REG
    yuediaoyuerou = { coeff = 'REG', vals = {10} },     -- 越钓越肉：每分钟鱼 10×REG
    duoduoyishan = { coeff = 'REG', vals = {5} },    -- 多多益善：金币 = 实际召唤数 × 5 × REG（单轮封顶30只，金币跟随实际虫子，每只基础5金币、品质线性缩放）
    zidongfanmai = { arr = {4, 4, 4, 4, 4} },           -- 自动贩卖机：每条鱼按商店价 4 金币贩卖（不随品质变化，__2__恒为4）
    huoliyu = { arr = {1, 1, 2, 2, 3} },                -- 每85条鱼 +__2__活力(11223)
}

-- 学天赋时调用一次：宠物直接返回品质整数 1..5
-- tier: 'low'(默认,普通购买) / 'mid'(中级购买) / 'high'(高级购买)，对应宠物 quality_weights 三档
function Public.roll(tier)
    return pet.roll_quality(tier or 'low')
end

-- 运行时取品质：字典直接 O(1) 取值（方案 D 简化版，无需旧档兼容/遍历）。
-- 找不到 / 未学 / 已删 → 返回 1（普通），不崩。
function Public.idx(player, skill_id)
    local this = WPT.get()
    if not player or not skill_id then return 1 end
    local skills = this.skill and this.skill[player.name]
    if skills and skills[skill_id] ~= nil then
        return skills[skill_id]
    end
    return 1
end

-- 仅 UI 展示时派生
function Public.name(q)
    return NAMES[q] or NAMES[1]
end

-- 返回本地化品质名（用于 game.print / GUI caption）
function Public.locale_name(q)
    return { 'tianfu.quality_' .. (q or 1) }
end

-- 返回 0-255 系 {r,g,b}（Factorio GUI font_color / print color 需 /255）
function Public.color(q)
    return pet.quality_colors[q]
end

-- 返回 GUI sprite 路径（Factorio 2.0 quality 图标）
function Public.icon(q)
    return QUALITY_SPRITES[q] or QUALITY_SPRITES[1]
end

-- 描述注入参数：返回 {品质名, 数值1, 数值2, ...}，供 GUI 用 table.unpack 展开填入 __1__ __2__ ...
-- 没有 DISPLAY 项的天赋（成品类等）只返回品质名，向后兼容。
-- 取整规则（用户 2026-07-14）：基准值为整数→math.floor（严格对齐游戏内）；基准值本身为小数→不取整，限 2 位小数。
-- 模式：vals×coeff（系数缩放） / arr（单个显式逐档值） / arrs（多个显式逐档值）。
function Public.tip_args(id, q)
    q = q or 1
    local args = { Public.locale_name(q) }
    local d = DISPLAY[id]
    if not d then return args end
    -- 整个公式随品质缩放（如 mbz 敏捷=公式×REG）：直接注入系数小数，描述用「×__2__倍」呈现
    if d.mult then
        local coeff = (d.mult == 'REG') and COEFF_REG or COEFF_LOW
        args[#args + 1] = fmt2(coeff[q])
        return args
    end
    local function emit(v)
        if v == nil then
            args[#args + 1] = '?'
        elseif math.floor(v) == v then
            args[#args + 1] = qround(v)        -- 整数（含整数基准×系数）：math.floor 对齐游戏
        else
            args[#args + 1] = fmt2(v)           -- 小数基准：不取整，限 2 位小数
        end
    end
    if d.arrs then
        for i = 1, #d.arrs do emit(d.arrs[i][q]) end
    elseif d.arr then
        emit(d.arr[q])
    elseif d.vals then
        for i = 1, #d.vals do
            local e = d.vals[i]
            local v, ct
            if type(e) == 'table' then
                v = e.v; ct = e.c
            else
                v = e; ct = d.coeff
            end
            if v == nil then
                args[#args + 1] = '?'
            else
                local coeff = (ct == 'REG') and COEFF_REG or COEFF_LOW
                local product = v * coeff[q]
                if math.floor(v) == v then
                    args[#args + 1] = qround(product)   -- 整数基准×系数：floor 对齐游戏
                else
                    args[#args + 1] = fmt2(product)
                end
            end
        end
    end
    return args
end

-- 四舍五入（供 skill 文件在应用品质系数时调用，保证游戏内数值与描述一致）
function Public.qround(x)
    return qround(x)
end

return Public
