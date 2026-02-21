/*
	样条流程工具箱 v3.5.4
	适用于 3ds Max 2024 中文版
	功能：稳定描摹 / 批量附加 / 炸开到对象 / 一键挤出 / 一键加壳 / 轴心居中 / 复制粘贴

	安装方法：
	1. 将此文件拖入 3ds Max 视口即可运行
	2. 或者通过菜单：脚本 -> 运行脚本 -> 选择此文件
*/

try(destroyDialog rolFixBlackFace) catch()
callbacks.removeScripts id:#fixBlackFaceSelChanged

global splineToolboxScriptPath = undefined
global splineToolboxUIIniPath = undefined
try(splineToolboxScriptPath = getSourceFileName()) catch()
try(splineToolboxUIIniPath = pathConfig.appendPath (getDir #plugcfg) "spline_toolbox_ui.ini") catch()

fn toIntOrDefault val defaultVal =
(
	if (val == undefined) or (val == "") then
		defaultVal
	else
	(
		local parsed = defaultVal
		try(parsed = val as integer) catch(parsed = defaultVal)
		parsed
	)
)

fn loadToolboxDialogPos =
(
	if splineToolboxUIIniPath == undefined then return undefined

	local sx = getINISetting splineToolboxUIIniPath "UI" "PosX"
	local sy = getINISetting splineToolboxUIIniPath "UI" "PosY"
	if (sx == "") or (sy == "") then return undefined

	local x = toIntOrDefault sx 120
	local y = toIntOrDefault sy 120
	[x, y]
)

fn saveToolboxDialogPos p =
(
	if (p == undefined) or (splineToolboxUIIniPath == undefined) then return false
	setINISetting splineToolboxUIIniPath "UI" "PosX" ((p.x as integer) as string)
	setINISetting splineToolboxUIIniPath "UI" "PosY" ((p.y as integer) as string)
	true
)

rollout rolFixBlackFace "样条流程工具箱 v3.5.4" width:340 height:885
(
	group "顶部信息"
	(
		label lbSelectTitle "选择信息：先选中对象，再点击对应功能" align:#left width:310
		label lbSelInfo "" align:#left width:310
		label lbSelStats "" align:#left width:310
		label lbInfo "程序信息：就绪" align:#left width:310 height:18
	)

	timer tmrClock interval:1000 active:false

	group "描摹重建"
	(
		label lbTrace "用于黑面修复的稳定点描流程（支持多选）" align:#left width:310
		button btnTrace "描摹样条线" width:310 height:34 toolTip:"保留曲线切线的重建样条"
		checkbox chkTraceAutoSimplify "描摹时自动精简点" checked:false
		checkbox chkDeleteOrig "描摹后删除原物体" checked:true
	)

	group "样条处理"
	(
		button btnAttach "批量附加" width:310 height:34 toolTip:"将多个样条线合并为一个对象"
		button btnExplode "炸开到对象" width:310 height:34 toolTip:"将每条子样条线分离为独立对象"
	)

	group "点数优化"
	(
		spinner spnSimplifyTol "偏差容差(mm): " range:[0.001,10000,1.0] type:#float width:220 fieldwidth:70 align:#left
		spinner spnWeldTol "焊接阈值(mm): " range:[0.0,10000,0.1] type:#float width:220 fieldwidth:70 align:#left
		button btnSimplify "精简样条点" width:310 height:34 toolTip:"RDP高速精简：曲线自动平滑 + 防毛刺"
	)

	group "体量生成"
	(
		spinner spnExtrude "挤出高度: " range:[-99999,99999,10] type:#float width:220 fieldwidth:70 align:#left
		button btnExtrude "一键挤出" width:310 height:34 toolTip:"为样条线添加 Extrude"
		spinner spnShell "加壳厚度: " range:[0.001,99999,2] type:#float width:220 fieldwidth:70 align:#left
		button btnShell "一键加壳" width:310 height:34 toolTip:"为对象添加 Shell"
	)

	group "轴心与复制"
	(
		button btnCenterPivot "重置轴-仅影响轴-居中到对象" width:310 height:34 toolTip:"将当前选中物体的轴心居中到对象"
		button btnCopyNodes "复制" width:150 height:34 across:2
		button btnPasteNodes "粘贴" width:150 height:34
	)

	group "显示与冻结"
	(
		button btnFreezeSel "冻结当前选择" width:150 height:34 across:2
		button btnUnfreezeAll "全部取消冻结" width:150 height:34
		button btnHideSel "隐藏当前选择" width:150 height:34 across:2
		button btnUnhideAll "全部取消隐藏" width:150 height:34
	)

	group "插件维护"
	(
		button btnReloadTool "重载插件" width:310 height:34 toolTip:"重新载入当前工具脚本"
	)

	dotNetControl dnClock "System.Windows.Forms.Label" width:310 height:36

	fn updateInfo msg =
	(
		lbInfo.text = "程序信息：" + msg
	)

	fn updateClock =
	(
		local nowText = ""
		try(nowText = ((dotNetClass "System.DateTime").Now.ToString "yyyy-MM-dd HH:mm:ss")) catch(nowText = localTime as string)
		dnClock.text = nowText
	)

	fn updateSelInfo =
	(
		local selCount = selection.count
		local pointCount = 0
		local lineCount = 0
		local faceCount = 0

		for obj in selection do
		(
			if not isValidNode obj then continue

			if superClassOf obj == Shape then
			(
				local splineCount = numSplines obj
				for s = 1 to splineCount do
				(
					local knotCount = numKnots obj s
					pointCount += knotCount

					local segCount = 0
					try(segCount = numSegments obj s) catch(segCount = 0)
					if segCount == 0 then
					(
						if isClosed obj s then
							segCount = knotCount
						else if knotCount > 0 then
							segCount = knotCount - 1
						else
							segCount = 0
					)
					lineCount += segCount
				)
			)
			else
			(
				local msh = undefined
				try(msh = snapshotAsMesh obj) catch(msh = undefined)
				if msh != undefined then
				(
					pointCount += msh.numVerts
					faceCount += msh.numFaces
					local edgeCount = 0
					try(edgeCount = meshop.getNumEdges msh) catch(edgeCount = 0)
					lineCount += edgeCount
					free msh
				)
			)
		)

		lbSelInfo.text = "当前选择：" + selCount as string + " 个物体"
		lbSelStats.text = "点: " + pointCount as string + "  线: " + lineCount as string + "  面: " + faceCount as string
	)

	fn getCopyPasteFile =
	(
		local copyDir = getDir #autoback
		pathConfig.appendPath copyDir "pastefile.max"
	)

	fn reloadToolSelf =
	(
		local scriptPath = splineToolboxScriptPath
		if (scriptPath == undefined) or (scriptPath == "") then
		(
			scriptPath = getOpenFileName caption:"选择要重载的工具脚本" types:"MaxScript (*.ms)|*.ms|"
			if (scriptPath != undefined) and (scriptPath != "") then
				splineToolboxScriptPath = scriptPath
		)

		if (scriptPath == undefined) or (scriptPath == "") then
		(
			updateInfo "重载取消：未选择脚本文件"
			return false
		)

		if not doesFileExist scriptPath then
		(
			messageBox ("未找到脚本文件：\n" + scriptPath) title:"重载失败"
			return false
		)

		callbacks.removeScripts id:#fixBlackFaceSelChanged
		try(destroyDialog rolFixBlackFace) catch()

		try
		(
			fileIn scriptPath quiet:true
			true
		)
		catch
		(
			messageBox ("重载失败，请检查脚本语法：\n" + scriptPath) title:"重载失败"
			false
		)
	)

	fn pointToLineDistance p a b =
	(
		local ab = b - a
		local abLen = length ab
		if abLen < 0.000001 then
			distance p a
		else
		(
			local ap = p - a
			local t = (dot ap ab) / (abLen * abLen)
			if t < 0.0 then t = 0.0
			if t > 1.0 then t = 1.0
			local proj = a + ab * t
			distance p proj
		)
	)

	fn countKeepBits keepArr maxCount =
	(
		local c = 0
		for i = 1 to maxCount do if keepArr[i] do c += 1
		c
	)

	fn max2 a b =
	(
		if a > b then a else b
	)

	fn rdpKeepOpenByTol pts distTol =
	(
		local n = pts.count
		local keep = #{}
		if n < 1 then return keep

		keep[1] = true
		if n > 1 then keep[n] = true
		if n <= 2 then return keep

		local stackS = #()
		local stackE = #()
		append stackS 1
		append stackE n

		while stackS.count > 0 do
		(
			local top = stackS.count
			local s = stackS[top]
			local e = stackE[top]
			deleteItem stackS top
			deleteItem stackE top

			if (e - s) > 1 then
			(
				local a = pts[s]
				local b = pts[e]
				local maxDist = -1.0
				local maxI = 0

				for i = (s + 1) to (e - 1) do
				(
					local d = pointToLineDistance pts[i] a b
					if d > maxDist then
					(
						maxDist = d
						maxI = i
					)
				)

				if (maxI > 0) and (maxDist > distTol) then
				(
					keep[maxI] = true
					append stackS s
					append stackE maxI
					append stackS maxI
					append stackE e
				)
			)
		)
		keep
	)

	fn preserveSharpCorners pts keepArr isClosedSpline angleLimitDeg =
	(
		local n = pts.count
		if n < 3 then return keepArr

		local dotLimit = cos angleLimitDeg
		if isClosedSpline then
		(
			for i = 1 to n do
			(
				local prevI = if i == 1 then n else (i - 1)
				local nextI = if i == n then 1 else (i + 1)
				local v1 = pts[prevI] - pts[i]
				local v2 = pts[nextI] - pts[i]

				if ((length v1) > 0.000001) and ((length v2) > 0.000001) then
				(
					local d = dot (normalize v1) (normalize v2)
					if d > dotLimit then keepArr[i] = true
				)
			)
		)
		else
		(
			for i = 2 to (n - 1) do
			(
				local v1 = pts[i - 1] - pts[i]
				local v2 = pts[i + 1] - pts[i]

				if ((length v1) > 0.000001) and ((length v2) > 0.000001) then
				(
					local d = dot (normalize v1) (normalize v2)
					if d > dotLimit then keepArr[i] = true
				)
			)
		)
		keepArr
	)

	fn denoisePointsForRDP pts isClosedSpline distTol =
	(
		local n = pts.count
		if n < 3 then return pts

		local curr = #()
		for i = 1 to n do append curr pts[i]

		for pass = 1 to 2 do
		(
			local nextPts = #()
			for i = 1 to n do
			(
				local p = curr[i]
				if (not isClosedSpline) and (i == 1 or i == n) then
				(
					append nextPts p
				)
				else
				(
					local prevI = if i == 1 then n else (i - 1)
					local nextI = if i == n then 1 else (i + 1)
					local pPrev = curr[prevI]
					local pNext = curr[nextI]
					local v1 = pPrev - p
					local v2 = pNext - p
					local l1 = length v1
					local l2 = length v2

					if (l1 < 0.000001) or (l2 < 0.000001) then
					(
						append nextPts p
					)
					else
					(
						local d = dot (normalize v1) (normalize v2)
						if d > -0.60 then
						(
							-- 拐角点保持不动
							append nextPts p
						)
						else
						(
							local pNew = (pPrev + p * 2.0 + pNext) / 4.0
							if (distance pNew p) <= (distTol * 1.5) then
								append nextPts pNew
							else
								append nextPts p
						)
					)
				)
			)
			curr = nextPts
		)
		curr
	)

	fn preserveCurveKnots shp splineIndex candidateIndices keepArr distTol weldTol =
	(
		local n = candidateIndices.count
		local protectLen = max2 (distTol * 1.2) (weldTol * 8.0)

		for i = 1 to n do
		(
			local k = candidateIndices[i]
			local p = getKnotPoint shp splineIndex k
			local inV = getInVec shp splineIndex k
			local outV = getOutVec shp splineIndex k
			local h1 = distance p inV
			local h2 = distance p outV
			local hMax = max2 h1 h2

			if hMax >= protectLen then
				keepArr[i] = true
		)
		keepArr
	)

	fn isCurveSplineByHandles shp splineIndex distTol weldTol =
	(
		local kc = numKnots shp splineIndex
		local protectLen = max2 (distTol * 1.2) (weldTol * 8.0)

		for k = 1 to kc do
		(
			local p = getKnotPoint shp splineIndex k
			local inV = getInVec shp splineIndex k
			local outV = getOutVec shp splineIndex k
			local hMax = max2 (distance p inV) (distance p outV)
			if hMax >= protectLen then return true
		)
		false
	)

	fn fixSplineAfterSimplify shp splineIndex preferSmooth:false =
	(
		local isClosedSpline = false
		try(isClosedSpline = isClosed shp splineIndex) catch(isClosedSpline = false)

		local kc = numKnots shp splineIndex
		if kc < 2 then return false

		if preferSmooth and (not isClosedSpline) and (kc == 2) then
		(
			local p1 = getKnotPoint shp splineIndex 1
			local p2 = getKnotPoint shp splineIndex 2
			local v = p2 - p1
			local lenV = length v
			if lenV > 0.000001 then
			(
				local dir = normalize v
				local h = lenV * 0.3333
				local in1 = p1 - dir * h
				local out1 = p1 + dir * h
				local in2 = p2 - dir * h
				local out2 = p2 + dir * h

				try(setKnotType shp splineIndex 1 #bezier) catch()
				try(setKnotType shp splineIndex 2 #bezier) catch()
				try(setInVec shp splineIndex 1 in1) catch()
				try(setOutVec shp splineIndex 1 out1) catch()
				try(setInVec shp splineIndex 2 in2) catch()
				try(setOutVec shp splineIndex 2 out2) catch()
				try(setSegType shp splineIndex 1 #curve) catch()
			)
			return true
		)

		for k = 1 to kc do
		(
			local p = getKnotPoint shp splineIndex k
			local prevK = if k == 1 then (if isClosedSpline then kc else 1) else (k - 1)
			local nextK = if k == kc then (if isClosedSpline then 1 else kc) else (k + 1)
			local pPrev = getKnotPoint shp splineIndex prevK
			local pNext = getKnotPoint shp splineIndex nextK

			if (not isClosedSpline) and (k == 1 or k == kc) then
			(
				try(setKnotType shp splineIndex k #corner) catch()
				try(setInVec shp splineIndex k p) catch()
				try(setOutVec shp splineIndex k p) catch()
			)
			else
			(
				local v1 = pPrev - p
				local v2 = pNext - p
				local l1 = length v1
				local l2 = length v2

				if (l1 < 0.000001) or (l2 < 0.000001) then
				(
					try(setKnotType shp splineIndex k #corner) catch()
					try(setInVec shp splineIndex k p) catch()
					try(setOutVec shp splineIndex k p) catch()
				)
				else
				(
					local d = dot (normalize v1) (normalize v2)
					local cornerLimit = if preferSmooth then -0.35 else -0.75
					if d > cornerLimit then
					(
						-- 拐角保持直线，避免过冲
						try(setKnotType shp splineIndex k #corner) catch()
						try(setInVec shp splineIndex k p) catch()
						try(setOutVec shp splineIndex k p) catch()
					)
					else
					(
						local tan = pNext - pPrev
						if (length tan) < 0.000001 then
						(
							try(setKnotType shp splineIndex k #corner) catch()
							try(setInVec shp splineIndex k p) catch()
							try(setOutVec shp splineIndex k p) catch()
						)
						else
						(
							local dir = normalize tan
							local minLen = if l1 < l2 then l1 else l2
							local handleLen = minLen * 0.25
							local inV = p - dir * handleLen
							local outV = p + dir * handleLen

							try(setKnotType shp splineIndex k #smooth) catch()
							try(setInVec shp splineIndex k inV) catch()
							try(setOutVec shp splineIndex k outV) catch()
						)
					)
				)
			)
		)
		true
	)

	fn simplifySplineByTolerance shp splineIndex distTol weldTol maxPasses:20 =
	(
		local isClosedSpline = isClosed shp splineIndex
		local kc = numKnots shp splineIndex
		local curveHint = isCurveSplineByHandles shp splineIndex distTol weldTol
		if isClosedSpline and kc < 4 then return 0
		if (not isClosedSpline) and kc < 3 then return 0

		local candidateIndices = #()
		append candidateIndices 1
		local lastKeepPos = getKnotPoint shp splineIndex 1

		for k = 2 to kc do
		(
			local p = getKnotPoint shp splineIndex k
			if (distance p lastKeepPos) > weldTol then
			(
				append candidateIndices k
				lastKeepPos = p
			)
		)

		if not isClosedSpline then
		(
			if candidateIndices[candidateIndices.count] != kc then append candidateIndices kc
		)
		else
		(
			if candidateIndices.count > 2 then
			(
				local pFirst = getKnotPoint shp splineIndex candidateIndices[1]
				local pLast = getKnotPoint shp splineIndex candidateIndices[candidateIndices.count]
				if (distance pFirst pLast) <= weldTol then deleteItem candidateIndices candidateIndices.count
			)
		)

		local cn = candidateIndices.count
		if isClosedSpline and cn < 3 then return 0
		if (not isClosedSpline) and cn < 2 then return 0

		local pts = #()
		for i = 1 to cn do append pts (getKnotPoint shp splineIndex candidateIndices[i])
		local evalPts = denoisePointsForRDP pts isClosedSpline distTol

		local keepCandidate = #{}
		if isClosedSpline then
		(
			local ptsOpen = #()
			for i = 1 to cn do append ptsOpen evalPts[i]
			append ptsOpen evalPts[1]
			local keepOpen = rdpKeepOpenByTol ptsOpen distTol
			for i = 1 to cn do if keepOpen[i] do keepCandidate[i] = true
		)
		else
		(
			keepCandidate = rdpKeepOpenByTol evalPts distTol
		)

		keepCandidate = preserveSharpCorners pts keepCandidate isClosedSpline 120.0
		keepCandidate = preserveCurveKnots shp splineIndex candidateIndices keepCandidate distTol weldTol

		if isClosedSpline then
		(
			if (countKeepBits keepCandidate cn) < 3 then
			(
				local i2 = (cn / 2) as integer
				if i2 < 1 then i2 = 1
				if i2 > cn then i2 = cn
				keepCandidate[1] = true
				keepCandidate[i2] = true
				keepCandidate[cn] = true
			)

			if curveHint and cn >= 4 and (countKeepBits keepCandidate cn) < 4 then
			(
				local i2 = (cn / 3) as integer
				local i3 = ((cn * 2) / 3) as integer
				if i2 < 2 then i2 = 2
				if i3 < 3 then i3 = 3
				if i2 > (cn - 1) then i2 = (cn - 1)
				if i3 > (cn - 1) then i3 = (cn - 1)
				keepCandidate[1] = true
				keepCandidate[i2] = true
				keepCandidate[i3] = true
				keepCandidate[cn] = true
			)
		)
		else
		(
			keepCandidate[1] = true
			keepCandidate[cn] = true

			if curveHint and cn >= 3 and (countKeepBits keepCandidate cn) < 3 then
			(
				local midI = (cn / 2) as integer
				if midI < 2 then midI = 2
				if midI > (cn - 1) then midI = (cn - 1)
				keepCandidate[midI] = true
			)
		)

		local keepOriginal = #{}
		for i = 1 to cn do
		(
			if keepCandidate[i] do keepOriginal[candidateIndices[i]] = true
		)

		if not isClosedSpline then
		(
			keepOriginal[1] = true
			keepOriginal[kc] = true
		)

		local minNeeded = if isClosedSpline then (if curveHint then 4 else 3) else (if curveHint then 3 else 2)
		if (countKeepBits keepOriginal kc) < minNeeded then return 0

		local removed = 0
		for k = kc to 1 by -1 do
		(
			if not keepOriginal[k] then
			(
				deleteKnot shp splineIndex k
				removed += 1
			)
		)

		if removed > 0 do
		(
			try(fixSplineAfterSimplify shp splineIndex preferSmooth:curveHint) catch()
		)
		removed
	)

	-- 计算闭合样条在本地XY平面的有符号面积（>0:逆时针，<0:顺时针）
	fn getSplineAreaXY shp splineIndex =
	(
		local knotCount = numKnots shp splineIndex
		if knotCount < 3 then return 0.0

		local area = 0.0
		for k = 1 to knotCount do
		(
			local nextK = if k < knotCount then (k + 1) else 1
			local p1 = getKnotPoint shp splineIndex k
			local p2 = getKnotPoint shp splineIndex nextK
			area += (p1.x * p2.y - p2.x * p1.y)
		)
		area * 0.5
	)

	-- 用临时挤出网格判断法线是否朝里（朝里返回 true）
	fn shouldReverseByProbe shpNode =
	(
		local hasClosed = false
		for s = 1 to (numSplines shpNode) do
		(
			if isClosed shpNode s then
			(
				hasClosed = true
				exit
			)
		)
		if not hasClosed then return false

		local tmp = undefined
		local score = 0.0
		local probeOK = false

		try
		(
			tmp = copy shpNode
			tmp.name = uniqueName (shpNode.name + "_probe")
			tmp.isHidden = true

			local ex = Extrude()
			ex.amount = 1.0
			ex.segments = 1
			ex.capStart = true
			ex.capEnd = true
			addModifier tmp ex

			convertToMesh tmp
			local msh = tmp.mesh
			if msh != undefined and msh.numVerts > 0 and msh.numFaces > 0 then
			(
				local center = [0,0,0]
				for v = 1 to msh.numVerts do center += getVert msh v
				center /= msh.numVerts

				for f = 1 to msh.numFaces do
				(
					local faceIdx = getFace msh f
					local p = ((getVert msh faceIdx.x) + (getVert msh faceIdx.y) + (getVert msh faceIdx.z)) / 3.0
					local n = getFaceNormal msh f
					score += dot n (p - center)
				)
				probeOK = true
			)
		)
		catch()

		if tmp != undefined and isValidNode tmp then delete tmp
		if not probeOK then return false
		(score < 0)
	)

	on btnTrace pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选中至少一个样条线物体！" title:"提示"
			return undefined
		)

		local srcObjs = selection as array
		local tracedObjs = #()
		local skipCount = 0
		local failCount = 0

		undo "描摹样条线(批量)" on
		(
			for obj in srcObjs do
			(
				if (isValidNode obj) and (superClassOf obj.baseObject == Shape) then
				(
					local newShape = undefined
					local modStates = #()

					for m = 1 to obj.modifiers.count do
					(
						append modStates obj.modifiers[m].enabled
						obj.modifiers[m].enabled = false
					)

					try
					(
						newShape = SplineShape()
						newShape.name = uniqueName (obj.name + "_描摹")

						local splineCount = numSplines obj
						local flattenZ = 0.0
						local flattenCnt = 0

						for s = 1 to splineCount do
						(
							local knotCountForZ = numKnots obj s
							for k = 1 to knotCountForZ do
							(
								flattenZ += (getKnotPoint obj s k).z
								flattenCnt += 1
							)
						)
						if flattenCnt > 0 then flattenZ /= flattenCnt

						for s = 1 to splineCount do
						(
							addNewSpline newShape
							local knotCount = numKnots obj s
							local closedSpline = isClosed obj s

							for k = 1 to knotCount do
							(
								local p = getKnotPoint obj s k
								local inV = getInVec obj s k
								local outV = getOutVec obj s k
								local kType = #corner

								try(kType = getKnotType obj s k) catch(kType = #corner)

								p = [p.x, p.y, flattenZ]
								inV = [inV.x, inV.y, flattenZ]
								outV = [outV.x, outV.y, flattenZ]

								local isCurveKnot = ((distance p inV) > 0.0001) or ((distance p outV) > 0.0001)

								if isCurveKnot then
									addKnot newShape s kType #curve p inV outV
								else
									addKnot newShape s kType #line p
							)

							if closedSpline and knotCount >= 3 then close newShape s
						)

						updateShape newShape

						-- 可选自动轻量精简，进一步减少点数
						if chkTraceAutoSimplify.checked then
						(
							for s = 1 to (numSplines newShape) do
								simplifySplineByTolerance newShape s (spnSimplifyTol.value * 0.5) spnWeldTol.value
							updateShape newShape
						)

						local refArea = 0.0
						for s = 1 to (numSplines newShape) do
						(
							if isClosed newShape s then
							(
								local a = getSplineAreaXY newShape s
								if abs a > abs refArea then refArea = a
							)
						)

						if refArea != 0.0 then
						(
							for s = 1 to (numSplines newShape) do
							(
								if isClosed newShape s then
								(
									local a = getSplineAreaXY newShape s
									if abs a < abs refArea and (a * refArea) > 0 then reverse newShape s
								)
							)
						)

						if shouldReverseByProbe newShape then
						(
							for s = 1 to (numSplines newShape) do reverse newShape s
						)
						updateShape newShape

						newShape.material = undefined
						newShape.wirecolor = (color 170 210 255)
					)
					catch
					(
						if newShape != undefined and isValidNode newShape then delete newShape
						newShape = undefined
					)

					if isValidNode obj then
					(
						local restoreCount = obj.modifiers.count
						if modStates.count < restoreCount then restoreCount = modStates.count
						for m = 1 to restoreCount do obj.modifiers[m].enabled = modStates[m]
					)

					if newShape != undefined and isValidNode newShape then
					(
						newShape.isHidden = false
						append tracedObjs newShape
						if chkDeleteOrig.checked and isValidNode obj then delete obj
					)
					else
					(
						failCount += 1
					)
				)
				else
				(
					skipCount += 1
				)
			)
		)

		if tracedObjs.count > 0 then
			select tracedObjs
		else
			clearSelection()

		updateSelInfo()
		if tracedObjs.count > 0 then
			updateInfo ("描摹完成：成功 " + tracedObjs.count as string + "，跳过 " + skipCount as string + "，失败 " + failCount as string)
		else
			updateInfo ("未完成描摹：跳过 " + skipCount as string + "，失败 " + failCount as string)
	)

	on btnAttach pressed do
	(
		local objs = selection as array
		if objs.count < 2 then
		(
			messageBox "请至少选择 2 条样条线！" title:"提示"
			return undefined
		)

		local allSplines = true
		for obj in objs do
		(
			if superClassOf obj != Shape then
			(
				allSplines = false
				exit
			)
		)
		if not allSplines then
		(
			messageBox "包含非样条线对象，请重新选择。" title:"提示"
			return undefined
		)

		undo "批量附加" on
		(
			convertToSplineShape objs[1]
			for i = 2 to objs.count do addAndWeld objs[1] objs[i] 0
			updateShape objs[1]
			select objs[1]
		)
		updateSelInfo()
		updateInfo ("批量附加完成：共 " + objs.count as string + " 条")
	)

	on btnExplode pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选择至少 1 个样条线对象！" title:"提示"
			return undefined
		)

		local srcObjs = selection as array
		local newObjs = #()
		local totalCount = 0
		local skipCount = 0

		undo "炸开到对象" on
		(
			for obj in srcObjs do
			(
				if superClassOf obj == Shape then
				(
					convertToSplineShape obj
					local sc = numSplines obj
					if sc > 1 then
					(
						for s = sc to 2 by -1 do
						(
							local newObj = copy obj
							for d = (numSplines newObj) to 1 by -1 do if d != s do deleteSpline newObj d
							updateShape newObj
							append newObjs newObj
						)
						for d = sc to 2 by -1 do deleteSpline obj d
						updateShape obj
					)
					totalCount += sc
				)
				else
				(
					skipCount += 1
				)
			)
		)

		local validSrc = for o in srcObjs where isValidNode o and superClassOf o == Shape collect o
		if (validSrc.count + newObjs.count) > 0 then select (validSrc + newObjs)

		updateSelInfo()
		if totalCount > 0 then
			updateInfo ("炸开完成：共 " + totalCount as string + " 条" + (if skipCount > 0 then ("，跳过 " + skipCount as string + " 个") else ""))
		else
			updateInfo "未找到可炸开的样条线对象"
	)

	on btnSimplify pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选择至少 1 个样条线对象！" title:"提示"
			return undefined
		)

		local objCount = 0
		local removedCount = 0
		local skipCount = 0
		local tol = spnSimplifyTol.value
		local weldTol = spnWeldTol.value

		undo "精简样条点" on
		(
			for obj in selection do
			(
				if superClassOf obj == Shape then
				(
					convertToSplineShape obj

					local localRemoved = 0
					for s = 1 to (numSplines obj) do
						localRemoved += simplifySplineByTolerance obj s tol weldTol

					updateShape obj
					objCount += 1
					removedCount += localRemoved
				)
				else
				(
					skipCount += 1
				)
			)
		)

		updateSelInfo()
		if objCount > 0 then
			updateInfo ("RDP精简完成：对象 " + objCount as string + "，删除点 " + removedCount as string + (if skipCount > 0 then ("，跳过 " + skipCount as string) else ""))
		else
			updateInfo "未找到样条线对象"
	)

	on btnExtrude pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选择至少 1 个样条线对象！" title:"提示"
			return undefined
		)

		local count = 0
		undo "一键挤出" on
		(
			for obj in selection do
			(
				if superClassOf obj == Shape then
				(
					addModifier obj (Extrude amount:spnExtrude.value)
					count += 1
				)
			)
		)

		updateSelInfo()
		if count > 0 then
			updateInfo ("一键挤出完成：共 " + count as string + " 个")
		else
			updateInfo "未找到样条线对象"
	)

	on btnShell pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选择至少 1 个对象！" title:"提示"
			return undefined
		)

		local count = 0
		undo "一键加壳" on
		(
			for obj in selection do
			(
				if (superClassOf obj == GeometryClass) or (superClassOf obj == Shape) then
				(
					addModifier obj (Shell outerAmount:spnShell.value innerAmount:0)
					count += 1
				)
			)
		)

		updateSelInfo()
		if count > 0 then
			updateInfo ("一键加壳完成：共 " + count as string + " 个")
		else
			updateInfo "未找到可加壳对象"
	)

	on btnCenterPivot pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选中至少一个物体！" title:"提示"
			return undefined
		)

		local pivotCount = 0
		undo "轴心居中到对象" on
		(
			for obj in selection do
			(
				if isValidNode obj then
				(
					CenterPivot obj
					pivotCount += 1
				)
			)
		)

		updateSelInfo()
		updateInfo ("已将 " + pivotCount as string + " 个物体的轴心居中")
	)

	on btnCopyNodes pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选中至少一个物体再复制！" title:"提示"
			return undefined
		)

		local copyFile = getCopyPasteFile()
		saveNodes selection copyFile
		updateSelInfo()
		updateInfo ("已复制 " + selection.count as string + " 个物体")
	)

	on btnPasteNodes pressed do
	(
		local copyFile = getCopyPasteFile()
		if not doesFileExist copyFile then
		(
			messageBox "未找到可粘贴的数据，请先点击「复制」。" title:"提示"
			return undefined
		)

		mergeMaxFile copyFile #select
		updateSelInfo()
		updateInfo "粘贴完成：已合并并选中物体"
	)

	on btnFreezeSel pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选中至少一个物体！" title:"提示"
			return undefined
		)

		local count = 0
		undo "冻结当前选择" on
		(
			for obj in selection do
			(
				if isValidNode obj then
				(
					obj.isFrozen = true
					count += 1
				)
			)
		)
		updateSelInfo()
		updateInfo ("已冻结 " + count as string + " 个物体")
	)

	on btnUnfreezeAll pressed do
	(
		local count = 0
		undo "全部取消冻结" on
		(
			for obj in objects do
			(
				if isValidNode obj and obj.isFrozen then
				(
					obj.isFrozen = false
					count += 1
				)
			)
		)
		updateSelInfo()
		updateInfo ("已取消冻结 " + count as string + " 个物体")
	)

	on btnHideSel pressed do
	(
		if selection.count == 0 then
		(
			messageBox "请先选中至少一个物体！" title:"提示"
			return undefined
		)

		local count = 0
		undo "隐藏当前选择" on
		(
			for obj in selection do
			(
				if isValidNode obj then
				(
					obj.isHidden = true
					count += 1
				)
			)
		)
		updateSelInfo()
		updateInfo ("已隐藏 " + count as string + " 个物体")
	)

	on btnUnhideAll pressed do
	(
		local count = 0
		undo "全部取消隐藏" on
		(
			for obj in objects do
			(
				if isValidNode obj and obj.isHidden then
				(
					obj.isHidden = false
					count += 1
				)
			)
		)
		updateSelInfo()
		updateInfo ("已取消隐藏 " + count as string + " 个物体")
	)

	on btnReloadTool pressed do
	(
		reloadToolSelf()
	)

	on tmrClock tick do
	(
		updateClock()
	)

	on rolFixBlackFace open do
	(
		local savedPos = loadToolboxDialogPos()
		if savedPos != undefined then
		(
			try(setDialogPos rolFixBlackFace savedPos) catch()
		)

		try(dnClock.textAlign = (dotNetClass "System.Drawing.ContentAlignment").MiddleCenter) catch()
		try(dnClock.font = dotNetObject "System.Drawing.Font" "Microsoft YaHei UI" 20.0 ((dotNetClass "System.Drawing.FontStyle").Bold)) catch()

		updateSelInfo()
		updateClock()
		tmrClock.active = true
		updateInfo "就绪 - 请选择对象后执行功能"
		callbacks.addScript #selectionSetChanged "if rolFixBlackFace != undefined do rolFixBlackFace.updateSelInfo()" id:#fixBlackFaceSelChanged
	)

	on rolFixBlackFace close do
	(
		tmrClock.active = false

		local dlgPos = undefined
		try(dlgPos = getDialogPos rolFixBlackFace) catch(dlgPos = undefined)
		if dlgPos != undefined do saveToolboxDialogPos dlgPos

		callbacks.removeScripts id:#fixBlackFaceSelChanged
	)
)

createDialog rolFixBlackFace style:#(#style_titlebar, #style_sysmenu, #style_toolwindow)
