local Declare = require 'utils.test.declare'
local Assert = require 'utils.test.assert'
local TianfuQuality = require 'maps.amap.tianfu_quality'

Declare.module(
    {'maps', 'amap', 'TianfuQuality'},
    function()
        Declare.test(
            'COEFF_REG quality coefficient mapping',
            function()
                -- 品质系数表项目约定：普通1.0/精良1.2/稀有1.4/史诗1.6/传说1.8
                -- rich_son = {coeff='REG', vals={7000}} → 基准×系数 floor
                local args_q1 = TianfuQuality.tip_args('rich_son', 1)
                local args_q2 = TianfuQuality.tip_args('rich_son', 2)
                local args_q3 = TianfuQuality.tip_args('rich_son', 3)
                local args_q4 = TianfuQuality.tip_args('rich_son', 4)
                local args_q5 = TianfuQuality.tip_args('rich_son', 5)
                Assert.equal(7000, args_q1[2])
                Assert.equal(8400, args_q2[2])   -- 7000 * 1.2
                Assert.equal(9800, args_q3[2])   -- 7000 * 1.4
                Assert.equal(11200, args_q4[2])  -- 7000 * 1.6
                Assert.equal(12600, args_q5[2])  -- 7000 * 1.8
            end
        )

        Declare.test(
            'COEFF_LOW tier uses same value table',
            function()
                -- hc = {coeff='LOW', vals={5}} → 5 * coeff
                local args = TianfuQuality.tip_args('hc', 5)
                Assert.equal(9, args[2]) -- 5 * 1.8
            end
        )

        Declare.test(
            'mult mode injects coefficient decimal',
            function()
                -- rsrl = {mult='LOW'} → 直接注入系数小数（fmt2）
                local args = TianfuQuality.tip_args('rsrl', 3)
                Assert.equal('1.4', args[2])
            end
        )

        Declare.test(
            'arr mode uses explicit per-quality values',
            function()
                -- shoucuo_de_shen = {arr={1,2,3,4,5}} → 逐档显式
                local args = TianfuQuality.tip_args('shoucuo_de_shen', 4)
                Assert.equal(4, args[2])
            end
        )

        Declare.test(
            'qround floors like in-game math',
            function()
                Assert.equal(3, TianfuQuality.qround(3.7))
                Assert.equal(4, TianfuQuality.qround(4.0))
                Assert.equal(-1, TianfuQuality.qround(-0.5))
            end
        )

        Declare.test(
            'quality name and locale mapping',
            function()
                Assert.equal('传说', TianfuQuality.name(5))
                Assert.table_equal({'tianfu.quality_3'}, TianfuQuality.locale_name(3))
                Assert.equal('普通', TianfuQuality.name(99)) -- 越界兜底 NAMES[1]
            end
        )

        Declare.test(
            'roll quality returns valid index',
            function()
                for _ = 1, 50 do
                    local q = TianfuQuality.roll('low')
                    Assert.is_true(q >= 1 and q <= 5 and math.floor(q) == q, 'quality index out of range: ' .. tostring(q))
                end
            end
        )
    end
)
