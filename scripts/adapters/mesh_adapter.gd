class_name MeshAdapter
extends PluginAdapter

## THE ONE DOOR TO `IxMesh` — Nearby peers, events, proximity and bandwidth.
##
## It knows the name and the two engine calls that use it, and nothing else.
## Everything shared — the absent line, the version handshake, the degrade, the
## two honest questions — is in `plugin_adapter.gd`.

const SINGLETON := "IxMesh"


func singleton_name() -> String:
	return SINGLETON


func present() -> bool:
	return Engine.has_singleton(SINGLETON)


func fetch() -> Object:
	return Engine.get_singleton(SINGLETON)
