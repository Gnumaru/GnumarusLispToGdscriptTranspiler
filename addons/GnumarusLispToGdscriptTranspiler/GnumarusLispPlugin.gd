## Dumb editor proxy for the Gnumarus Lisp addon.
##
## Per the addon rule, this class holds no logic: it instantiates
## GnumarusLispPluginImpl in _init (passing itself) and every function below
## only delegates to the identically-named implementation method.
@tool
class_name GnumarusLispPlugin
extends EditorPlugin


## Implementation script, loaded by path.
const PluginImplScript = preload("res://addons/GnumarusLispToGdscriptTranspiler/GnumarusLispPluginImpl.gd")


## Real implementation (built in _init, kept alive by this reference).
var _impl: RefCounted


## Constructor: builds the implementation with a reference to this proxy.
func _init() -> void:
	_impl = PluginImplScript.new(self)


## Registers the addon with the editor (delegated).
func _enter_tree() -> void:
	_impl._enter_tree()


## Unregisters the addon from the editor (delegated).
func _exit_tree() -> void:
	_impl._exit_tree()
