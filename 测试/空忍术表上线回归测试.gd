extends SceneTree

## 离线门：**服务端"一个忍术都没有"也是权威结论**，客户端必须把离线示例数据编的假技能清掉。
##
## 2026-11-24 用户报：新账号 4 级角色，技能栏里有 1、2 两个技能，一按就提示
## 「这个技能还没有学习」。服务端日志：
##   `[combat] rejected skill … skill=1001001 learned=False defined=True`
## 角色档 `skills = {}` —— 新角色本来就没学过任何忍术，服务端 WARP 帧的
## `skillInfoList` 是 `-`（`fake_flash_server._encode_skill_list`）。
##
## 客户端这一侧的漏洞：`_apply_skill_list_text()` 一看到 `-`/空串就 **return**，
## 于是 `server_skills_loaded` 永远是 false，`learned_skills` 里那几条
## **离线编的**（`离线示例数据.gd` 的 1001001 / 0001001 / 0002000…）一直留着，
## `_rebuild_skill_slots()` 把它们照旧排进技能槽。按下去发 1001001，服务端查不到
## `state.skills[1001001]` ⇒ 回「这个技能还没有学习」。
##
## 本门造一帧 `skillInfoList = "-"`，断言假技能必须消失。
##
## 运行：`"<Godot console>" --headless --path . --script res://测试/空忍术表上线回归测试.gd`

const 门名 := "空忍术表上线回归测试"
const 假技能号 := "1001001"		# `离线示例数据.gd` 编的第一条

var _后端: Node
var _会话: Node
var _红数 := 0
var _旧: Dictionary = {}


func _initialize() -> void:
	call_deferred("_跑")


func _跑() -> void:
	_后端 = root.get_node_or_null("BackendConnection")
	_会话 = root.get_node_or_null("GameSession")
	if _后端 == null or _会话 == null:
		_红("缺单例：BackendConnection=%s GameSession=%s" % [_后端, _会话])
		return
	_旧 = {
		"learned_skills": (_会话.learned_skills as Array).duplicate(true),
		"skill_slots": (_会话.skill_slots as Array).duplicate(true),
		"server_skills_loaded": bool(_会话.server_skills_loaded),
		"authoritative_skills": (_后端.authoritative_skills as Dictionary).duplicate(true),
		"in_game": bool(_后端.in_game),
	}
	# 摆成"刚登录、离线假技能还在"的样子
	_会话.server_skills_loaded = false
	_会话.learned_skills.assign([{
		"id": 假技能号, "name": "查克拉强化", "level": 1, "master_level": 0,
		"icon": "", "cooldown": 3.0, "power": 35,
	}])
	_会话._rebuild_skill_slots()
	var 槽里有 := false
	for 槽 in _会话.skill_slots:
		if String((槽 as Dictionary).get("id", "")) == 假技能号:
			槽里有 = true
	_查(槽里有, "前置条件没摆好：技能槽里本该有离线假技能 %s" % 假技能号)

	# 服务端说"一个忍术都没有"
	_后端.authoritative_skills.clear()
	_后端.call("_handle_warp_character_text", PackedStringArray(_造帧()))

	var 残留: Array[String] = []
	for 技能 in _会话.learned_skills:
		残留.append(String((技能 as Dictionary).get("id", "")))
	_查(残留.is_empty(),
			"服务端 skillInfoList = \"-\" 之后 learned_skills 该清空；实得 %s" % str(残留))
	_查(bool(_会话.server_skills_loaded),
			"收到空忍术表后 `server_skills_loaded` 该置 true（否则下次还会退回假技能）")
	var 槽残留: Array[String] = []
	for 槽 in _会话.skill_slots:
		var 号 := String((槽 as Dictionary).get("id", ""))
		if 号 != "":
			槽残留.append(号)
	_查(槽残留.is_empty(), "技能槽该全空；实得 %s" % str(槽残留))

	_还原()
	_收尾()


## 47 段：0..46。只填 `_handle_warp_character_text` 真读的那几格。
func _造帧() -> Array[String]:
	var 帧: Array[String] = []
	for _i in 47:
		帧.append("0")
	帧[0] = "38"
	帧[1] = "1"
	帧[3] = "1"
	帧[4] = "离线门"
	帧[5] = "1"
	帧[9] = "4"			# level（用户报的就是 4 级新号）
	帧[10] = "300"
	帧[15] = "100"
	帧[16] = "100"
	帧[17] = "100"
	帧[18] = "100"
	帧[23] = "101020000"
	帧[27] = "false"
	帧[31] = "0"
	帧[36] = "90"
	帧[37] = "-"
	帧[38] = "-"
	帧[39] = "-"
	帧[40] = "-"
	帧[41] = "-"			# skillInfoList：服务端"没有已学忍术"的原样
	帧[42] = "-"
	帧[43] = "48"
	帧[44] = "false"
	帧[45] = "false"
	帧[46] = "0"
	return 帧


func _还原() -> void:
	_会话.learned_skills.assign(_旧["learned_skills"])
	_会话.skill_slots.assign(_旧["skill_slots"])
	_会话.server_skills_loaded = bool(_旧["server_skills_loaded"])
	_后端.authoritative_skills = _旧["authoritative_skills"]
	_后端.in_game = _旧["in_game"]


func _查(过: bool, 文: String) -> void:
	if not 过:
		_红数 += 1
		print("!! " + 文)


func _红(文: String) -> void:
	_查(false, 文)
	if not _旧.is_empty():
		_还原()
	quit(1)


func _收尾() -> void:
	if _红数 == 0:
		print("%s：通过（skillInfoList=\"-\" ⇒ 离线假技能清空 / 技能槽全空 / server_skills_loaded=true）" % 门名)
		quit(0)
	else:
		print("%s：失败 %d 条" % [门名, _红数])
		quit(1)
