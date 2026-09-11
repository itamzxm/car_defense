-- entity_ref.lua — 实体引用安全存取（★ 毒值修复配套，2026-09-11）
--
-- 背景：Factorio 的 global/storage 禁止存 LuaEntity / LuaSurface / LuaChartTag（userdata 不可序列化）。
-- 毒值会让存档与多人地图下载的分块序列化（level.dat0..N）中途中断：
--   · 服务器照常运行（世界在内存里），但存档只有 level.dat0、无 metadata；
--   · 客户端加入时下载包缺世界数据 → cannot-load-downloaded-map("bad conversion")。
-- 规约：global 里一律存 record（unit_number + surface_index 两个数字），
-- 消费点用 resolve() 反查真实体（返回值保证 valid，失效返回 nil）。

local Public = {}

-- 创建/注册点调用：把实体转成可序列化 record（实体无效返回 nil）
function Public.record(entity)
  if not entity or not entity.valid then return nil end
  return { unit_number = entity.unit_number, surface_index = entity.surface_index }
end

-- 消费点调用：record → 真实实体（失效/未注册返回 nil，调用方必须判 nil）
function Public.resolve(rec)
  if not rec or not rec.unit_number then return nil end
  local surface = game.surfaces[rec.surface_index]
  if not surface or not surface.valid then return nil end
  local ents = surface.find_entities_filtered{ unit_number = rec.unit_number }
  if ents and ents[1] and ents[1].valid then return ents[1] end
  return nil
end

-- 兼容旧调用：直接传 entity 拆 record，传 record 原样返回
function Public.as_record(entity_or_rec)
  if not entity_or_rec then return nil end
  if entity_or_rec.unit_number and entity_or_rec.surface_index and type(entity_or_rec.unit_number) == 'number' then
    return entity_or_rec
  end
  return Public.record(entity_or_rec)
end

return Public
