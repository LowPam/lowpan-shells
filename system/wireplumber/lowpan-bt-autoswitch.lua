-- LowPan: quando uma saída de som Bluetooth aparece, ela vira a saída padrão.
-- Roda dentro do WirePlumber (sem processo extra). Só a saída: o microfone
-- fica como está, para o fone não cair no perfil HFP.

log = Log.open_topic ("s-lowpan-bt")

SimpleEventHook {
  name = "lowpan/bt-autoswitch",
  interests = {
    EventInterest {
      Constraint { "event.type", "=", "node-added" },
      Constraint { "media.class", "=", "Audio/Sink" },
      Constraint { "node.name", "matches", "bluez_output.*" },
    },
  },
  execute = function (event)
    local node = event:get_subject ()
    local name = node.properties ["node.name"]
    local om = event:get_source ():call ("get-object-manager", "metadata")
    local metadata = om:lookup { Constraint { "metadata.name", "=", "default" } }
    if metadata == nil or name == nil then
      return
    end
    log:info ("bluetooth conectado, saída padrão -> " .. name)
    metadata:set (0, "default.configured.audio.sink", "Spa:String:JSON",
        Json.Object { ["name"] = name }:to_string ())
  end
}:register ()
