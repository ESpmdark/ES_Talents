local ESTAL_Pending = CreateFrame("Frame", "ES_Talents_PendingTalents", UIParent)
ESTAL_Pending:Hide()

-- Localize functions
local SetSelection = C_Traits.SetSelection
local GetConfigInfo = C_Traits.GetConfigInfo
local GetTreeNodes = C_Traits.GetTreeNodes
local GetNodeInfo = C_Traits.GetNodeInfo
local GetConfigID = C_ClassTalents.GetActiveConfigID
local Purchase = C_Traits.PurchaseRank
local CanChangeTalents = C_ClassTalents.CanChangeTalents
local currSpec = C_SpecializationInfo.GetSpecialization
local setSpec = C_SpecializationInfo.SetSpecialization
-- Constants
local classFilename, classId = UnitClassBase("player")
local specCount = C_SpecializationInfo.GetNumSpecializationsForClassID(classId)
--

local function tblSortTal(a, b)
    if ( a.posY == b.posY ) then
		return a.posX < b.posX;
	else
		return a.posY < b.posY;
	end
end

local function getPlayerName()
	local name, _ = UnitFullName("player")
	local server = GetRealmName()
	server = server:gsub("%s+", "")
	return name .. "-" .. server
end

local function updateSpecBorder()
	for i=1,4 do
		ES_Talents_Main["Spec" .. i].Ring:SetAtlas("talents-node-circle-gray")
	end
	ES_Talents_Main["Spec" .. currSpec()].Ring:SetAtlas("talents-node-circle-yellow")
end

function ES_Talents_ActivateSpec(index)
	if currSpec() == index then
		PlaySound(110982, "Master", true)
		print('|cff00b4ffES_Talents: |rSpecialization already active!')
	else
		local success = setSpec(index)
		if not success then
			print('|cff00b4ffES_Talents: |r|cffff4141Could not activate specialization!')
		end
	end
end

function ES_Talents_ReadImport(importStream, treeID)
	local results = {};
	local treeNodes = GetTreeNodes(treeID);
	local success = true
	local msg1 = '|cff00b4ffES_Talents: |r|cffff4141Import string is corrupt, node type mismatch at nodeID: |r\n'
	local text = ""
	local msg2 = '\n|cffff4141String possibly out of date.|r'
	for _, treeNodeID in ipairs(treeNodes) do
		local nodeSelectedValue = importStream:ExtractValue(1)
		local isNodeSelected =  nodeSelectedValue == 1;
		local isNodePurchased = false;
		local isPartiallyRanked = false;
		local partialRanksPurchased = false;
		local isChoiceNode = false;
		local choiceNodeSelection = 0;
		local result = {}
		if (isNodeSelected) then
			local nodePurchasedValue = importStream:ExtractValue(1);
			isNodePurchased = nodePurchasedValue == 1;
			if(isNodePurchased) then
				local isPartiallyRankedValue = importStream:ExtractValue(1);
				isPartiallyRanked = isPartiallyRankedValue == 1;
				if(isPartiallyRanked) then
					partialRanksPurchased = importStream:ExtractValue(ClassTalentImportExportMixin.bitWidthRanksPurchased);
				end
				local isChoiceNodeValue = importStream:ExtractValue(1);
				isChoiceNode = isChoiceNodeValue == 1;
				if(isChoiceNode) then
					choiceNodeSelection = importStream:ExtractValue(2);
				end
				choiceNodeSelection = choiceNodeSelection + 1
				local entryID = false
				local treeNode = GetNodeInfo(GetConfigID(), treeNodeID)
				local isChoice = (treeNode.type == Enum.TraitNodeType.Selection) or (treeNode.type == Enum.TraitNodeType.SubTreeSelection);
				if isChoice then
					if (isChoice ~= isChoiceNode) then
						success = false
						text = text .. treeNodeID .. " "
					elseif (isChoiceNode and choiceNodeSelection) then
						entryID = treeNode.entryIDs[choiceNodeSelection];
					end
				elseif treeNode.activeEntry then
					entryID = treeNode.activeEntry.entryID;
				end
				if not entryID then
					entryID = treeNode.entryIDs[1];
				end
				result = {
					e = entryID,
					r = isPartiallyRanked and partialRanksPurchased or treeNode.maxRanks,
					c = (isChoiceNode and 1) or false,
					n = treeNode.ID,
					posX = ((treeNode.type == Enum.TraitNodeType.SubTreeSelection) and 1) or treeNode.posX,
					posY = ((treeNode.type == Enum.TraitNodeType.SubTreeSelection) and 1) or treeNode.posY
				}
				tinsert(results, result)
			end
		end
	end
	if success then table.sort(results, tblSortTal) end
	return results, success, msg1 .. text .. msg2
end

local function ES_ToggleAnimation(arg)
	local f = _G["ES_Talents_LoadingFrame"]
	local an = _G["ES_Talents_LoadingAnim"]
	if arg == "show" then
		if not f:IsVisible() then
			f:Show()
			an.ag:Play()
		end
	elseif f:IsVisible() then
		an.ag:Stop()
		f:Hide()
	end
end

local pendingTalents = {}
local pendingIdx = false
local pendingCount = 1
local function preparePending(t, count, curr)
	pendingTalents[curr] = t
	if count == curr then
		ES_ToggleAnimation("show")
		pendingCount = 1
		pendingIdx = 1
		ESTAL_Pending:Show()
	end
end

local function verifyImportStream(importStream,direct)
	local headerValid, serializationVersion, specID, _ = ClassTalentImportExportMixin:ReadLoadoutHeader(importStream);
	local currentSerializationVersion = C_Traits.GetLoadoutSerializationVersion();
	
	if(not headerValid) then
		print('|cff00b4ffES_Talents: |r|cffff4141Import failed!')
		print(LOADOUT_ERROR_BAD_STRING)
		PlaySound(29114, "Master", true)
		return false;
	end
	if(serializationVersion ~= currentSerializationVersion) then
		print('|cff00b4ffES_Talents: |r|cffff4141Import failed!')
		print(LOADOUT_ERROR_SERIALIZATION_VERSION_MISMATCH)
		print("Import-version: " .. serializationVersion)
		print("Current version: " .. currentSerializationVersion)
		PlaySound(29114, "Master", true)
		return false;
	end
	if direct and specID then
		return specID
	else
		if(specID ~= PlayerUtil.GetCurrentSpecID()) then
			print('|cff00b4ffES_Talents: |r|cffff4141Import failed!')
			print(LOADOUT_ERROR_WRONG_SPEC);
			PlaySound(29114, "Master", true)
			return false;
		end
	end
	return true
end

function ES_Talents_SaveDialog(name,import)
	local otherSpec = false
	local spec = PlayerUtil.GetCurrentSpecID()
	if import then
		local importStream = ExportUtil.MakeImportDataStream(import);
		local specID = verifyImportStream(importStream, true)
		if not specID then return false end
		if tonumber(specID) and not (specID == spec) then
			local _, specName, _, _, _, _, className = GetSpecializationInfoByID(specID)
			otherSpec = '|cff00b4ffES_Talents: |rSaved "' .. name .. '" for a different specialization (' .. specName .. '-' .. className .. ').'
			spec = specID
		end
	end
	if not ESTAL_DB["builds"][spec] then ESTAL_DB["builds"][spec] = {} end
	local success = false
	if ESTAL_DB["builds"][spec][name] then
		print('|cff00b4ffES_Talents: |r|cffff4141Save failed. This spec already has a build with that name!')
		PlaySound(29114, "Master", true)
	else
		ESTAL_DB["builds"][spec][name] = import or C_Traits.GenerateImportString(GetConfigID())
		success = true
		if otherSpec then print(otherSpec) end
	end
	return success
end

function ES_Talents_ImportBuild(importText)
	local importStream = ExportUtil.MakeImportDataStream(importText);
	if not verifyImportStream(importStream) then return false end
	local info = GetConfigInfo(GetConfigID())
	local loadoutContent, success, errorMsg = ES_Talents_ReadImport(importStream, info.treeIDs[1]);
	if success then
		local cID = GetConfigID()
		local info = GetConfigInfo(cID)
		C_Traits.ResetTree(cID, info.treeIDs[1])
		table.wipe(pendingTalents)
		preparePending(loadoutContent, 1, 1)
	else
		print(errorMsg)
		PlaySound(29114, "Master", true)
	end
	return success
end

function ES_Talents_Builds_Delete(self)
	local spec = PlayerUtil.GetCurrentSpecID()
	local db = ESTAL_DB["builds"][spec]
	MenuUtil.CreateContextMenu(UIParent, function(self, rootDescription)
		rootDescription:CreateTitle('|cffFF2F31Click to delete:|r')
		for k,v in pairs(db) do
			rootDescription:CreateButton(k, function() ESTAL_DB["builds"][spec][k] = nil; end)
		end
	end)
end

function ES_Talents_Builds_Load(self)
	self:SetupMenu(function(dropdown, rootDescription)
		local spec = PlayerUtil.GetCurrentSpecID()
		if not ESTAL_DB or not ESTAL_DB["builds"] then return end -- Function triggers once on load, before the init code has ran. Need this to catch that.
		local db = ESTAL_DB["builds"][spec] or {}
		local title = true
		for k,v in pairs(db) do
			if title then
				rootDescription:CreateButton('|cffFF2F31Delete a build|r', function() CloseDropDownMenus(); ES_Talents_Builds_Delete(); end)
				rootDescription:CreateTitle('|cff919191Click to apply:|r')
				title = false
			end
			rootDescription:CreateButton(k, function() CloseDropDownMenus(); ES_Talents_ImportBuild(v); end)
		end
		if title then
			rootDescription:CreateTitle('|cff919191empty|r')
		end
	end)
end

function ES_Talents_DeleteAutoBuild()
	local pn = getPlayerName()
	local spcID = PlayerUtil.GetCurrentSpecID()
	local db = ESTAL_DB["auto"][spcID]
	local sel = ESTAL_DB["player"][pn]["selected"][spcID]
	MenuUtil.CreateContextMenu(UIParent, function(self, rootDescription)
		local title = true
		for k,v in pairs(db) do
			if title then
				rootDescription:CreateTitle('|cffFF2F31Click to delete:|r')
				title = false
			end
			rootDescription:CreateButton(k, function() db[k] = nil; if (sel == k) then ESTAL_DB["player"][pn]["selected"][spcID] = false  ES_Talents_Main.AutoDD:SetDefaultText("No selection") ES_Talents_AutoDD_Load(ES_Talents_Main.AutoDD) end; end)
		end
		if title then
			rootDescription:CreateTitle('|cff919191empty|r')
		end
	end)
end

function ES_Talents_AutoDD_Load(self)
	self:SetupMenu(function(dropdown, rootDescription)
		local pn = getPlayerName()
		local spcID = PlayerUtil.GetCurrentSpecID()
		local builds = ESTAL_DB["auto"][spcID]
		local count = 0
		for k,v in pairs(builds) do
			if count > 0 then break end
			count = count + 1
		end
		rootDescription:CreateButton('|cffFFCC00Create new build|r', function() CloseDropDownMenus(); ES_Talents_Manager:Show(); end)
		if count > 0 then
			rootDescription:CreateButton('|cffFF2F31Delete a build|r', function() CloseDropDownMenus(); ES_Talents_DeleteAutoBuild(); end)
			rootDescription:CreateTitle('|cff919191Select build:|r')
			for name,_ in pairs(builds) do
				rootDescription:CreateButton(name, function() CloseDropDownMenus(); ES_Talents_applyAutoTalents(spcID, name); self:SetDefaultText(name); ESTAL_DB["player"][pn]["selected"][spcID] = name; end)
			end
		else
			rootDescription:CreateTitle('|cff919191empty|r')
		end
	end)
end

function ES_Talents_AutoToggle_OnClick(self)
	if self:GetChecked() then
		self:GetParent().AutoDD:Show();
		self.Text:SetText("")
		
		local pn = getPlayerName()
		local spcID = PlayerUtil.GetCurrentSpecID()
		local sel = ESTAL_DB["player"][pn]["selected"][spcID]
		if not sel then
			ES_Talents_Main.AutoDD:SetDefaultText("No selection")
		else
			ES_Talents_Main.AutoDD:SetDefaultText(sel)
			ES_Talents_applyAutoTalents(spcID,sel)
		end
	else
		self:GetParent().AutoDD:Hide();
		self.Text:SetText("Auto talent")
	end
	local pn = getPlayerName()
	ESTAL_DB["player"][pn].auto = self:GetChecked()
end

function ES_Talents_applyAutoTalents(spcID,sel)
	local tbl = ESTAL_DB["auto"][spcID][sel]
	local cID = GetConfigID()
	local info = GetConfigInfo(cID)
	C_Traits.ResetTree(cID, info.treeIDs[1])
	local hero = true
	table.wipe(pendingTalents)
	for i=1,#tbl do
		local importStream = ExportUtil.MakeImportDataStream(tbl[i]);
		if not verifyImportStream(importStream) then break end
	
		local loadoutContent, success, errorMsg = ES_Talents_ReadImport(importStream, info.treeIDs[1]);
		if success then
			preparePending(loadoutContent, #tbl, i)
		else
			print(errorMsg)
			PlaySound(29114, "Master", true)
		end
	end
end

local function ES_Talents_AvailablePoint()
	local str = ERR_TALENT_FAILED_UNSPENT_TALENT_POINTS
	local canChange, canAdd, changeError = CanChangeTalents()
	return changeError and (changeError == str)
end

function ES_Talents_Main_OnShow(self)
	local pn = getPlayerName()
	local auto = ESTAL_DB["player"][pn]["auto"]
	if not auto then return end
	local spcID = PlayerUtil.GetCurrentSpecID()
	local sel = ESTAL_DB["player"][pn]["selected"][spcID]
	if not sel then
		ES_Talents_Main.AutoDD:SetDefaultText("No selection")
		return
	else
		ES_Talents_Main.AutoDD:SetDefaultText(sel)
	end
	if not ESTAL_DB["auto"][spcID][sel] then
		ESTAL_DB["player"][pn]["selected"][spcID] = false
		ES_Talents_Main.AutoDD:SetDefaultText("No selection")
	elseif ES_Talents_AvailablePoint() then
		C_Timer.After(0.1, function()
			ES_Talents_applyAutoTalents(spcID, sel)
		end)
	end
end

function ES_Talents_Manager_Save(name,importstrings)
	local invalid = false
	for line in importstrings:gmatch("[^\r\n]+") do
		local importStream = ExportUtil.MakeImportDataStream(line);
		if not verifyImportStream(importStream) then
			invalid = true
			break
		end
		local info = GetConfigInfo(GetConfigID())
		local loadoutContent, success, errorMsg = ES_Talents_ReadImport(importStream, info.treeIDs[1]);
		if not success then
			invalid = true
			print(errorMsg)
			PlaySound(29114, "Master", true)
			break
		end
	end
	local success = false
	if not invalid then
		name = name or ""
		local spcID = PlayerUtil.GetCurrentSpecID()
		if not ESTAL_DB["auto"][spcID][name] then
			local tbl = {}
			for s in importstrings:gmatch("[^\r\n]+") do
				table.insert(tbl, s)
			end
			ESTAL_DB["auto"][spcID][name] = tbl
			success = true
		else
			print('|cff00b4ffES_Talents: |r|cffff4141A build with that name already exists!')
			PlaySound(29114, "Master", true)
		end
	end
	return success
end

local function ES_Talents_Pending(self,elapsed)
	if pendingIdx then
		local cID = GetConfigID()
		local v = pendingTalents[pendingIdx][pendingCount]
		if v and ES_Talents_AvailablePoint() then
			if v.c then
				SetSelection(cID, v.n, v.e)
			elseif v.r then
				for i=1,v.r do
					Purchase(cID, v.n)
				end
			end
			pendingCount = pendingCount + 1
		elseif pendingTalents[pendingIdx + 1] then
			pendingIdx = pendingIdx + 1
			pendingCount = 1
		else
			ES_ToggleAnimation("hide")
			pendingIdx = false
			ESTAL_Pending:Hide()
		end
	end
end
ESTAL_Pending:SetScript("OnUpdate", ES_Talents_Pending) -- Frame is hidden while not needed. Disabling the OnUpdate script

local firstOpen = true
function ES_Talents_InitFunc()
	local f = PlayerSpellsFrame.TalentsFrame
	if firstOpen and f and f:IsVisible() then
		-- Create Animation Object
		local anim = _G["ES_Talents_LoadingFrame"]
		if not anim then
			local f = CreateFrame("Frame", "ES_Talents_LoadingFrame", ES_Talents_Main)
			f:SetSize(100,100)
			f:SetPoint("BOTTOM", ES_Talents_Main, "TOP", 0, 50)
			f.f = f:CreateFontString(nil, "OVERLAY")
			f.f:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
			f.f:SetPoint("CENTER")
			f.f:SetText("Applying talents")
			local af = CreateFrame("Frame", "ES_Talents_LoadingAnim", f)
			af:SetAllPoints()
			af.t = af:CreateTexture()
			af.t:SetAllPoints()
			af.t:SetAtlas("UF-Essence-SpinnerOut", true)
			af.ag = af:CreateAnimationGroup()
			af.ag:SetLooping("REPEAT")
			af.ag.spin = af.ag:CreateAnimation("Rotation")
			af.ag.spin:SetDegrees(-360)
			af.ag.spin:SetDuration(0.75)
			f:Hide()
		end
		--//
		-- Populate DB if missing, or load existing data
		ESTAL_DB = ESTAL_DB or {}
		local pn = getPlayerName()
		local spcID = PlayerUtil.GetCurrentSpecID()
		if not ESTAL_DB["player"] then ESTAL_DB["player"] = {} end
		if not ESTAL_DB["builds"] then ESTAL_DB["builds"] = {} end
		if not ESTAL_DB["player"][pn] then
			ESTAL_DB["player"][pn] = { auto = false, selected = {[spcID] = false} }
		else
			local v = ESTAL_DB["player"][pn]
			if v.auto then
				ES_Talents_Main.AutoToggle:SetChecked(true)
				ES_Talents_Main.AutoToggle.Text:SetText("")
				ES_Talents_Main.AutoDD:Show()
				if v["selected"][spcID] then
					ES_Talents_Main.AutoDD:SetDefaultText(v["selected"][spcID])
				else
					ES_Talents_Main.AutoDD:SetDefaultText("No selection")
				end
			end
		end
		if not ESTAL_DB["auto"] then ESTAL_DB["auto"] = {} end
		if not ESTAL_DB["auto"][spcID] then ESTAL_DB["auto"][spcID] = {} end
		local sel = ESTAL_DB["player"][pn]["selected"][spcID]
		if not ESTAL_DB["auto"][spcID][sel] then
			ESTAL_DB["player"][pn]["selected"][spcID] = false
			ES_Talents_Main.AutoDD:SetDefaultText("No selection")
		end
		--//
		-- Set Spec buttons
		local rPerc, gPerc, bPerc, argbHex = GetClassColor(classFilename)
		
		for i=1,4 do
			local button = "Spec" .. i
			if i <= specCount then
				local _, name, _, icon, _ = C_SpecializationInfo.GetSpecializationInfo(i, false)
				local roletexture = TextureUtil.GetSmallIconForRoleEnum(GetSpecializationRoleEnum(i, false, false))
				SetPortraitToTexture(ES_Talents_Main[button].Icon, icon)
				ES_Talents_Main[button]:SetScript("OnEnter", function(self)
					GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 0)
					GameTooltip:SetText(CreateAtlasMarkup(roletexture, 16, 16) .. name, rPerc, gPerc, bPerc)
					GameTooltip:Show()
				end)
				ES_Talents_Main[button]:SetScript("OnLeave", function(self)
					GameTooltip_Hide();
				end)
			else
				ES_Talents_Main[button]:Hide()
			end
		end
		updateSpecBorder()
		ES_Talents_Main.Spec1:SetPoint("RIGHT", ES_Talents_Main, "LEFT", -(specCount * 40) + 10,0)
		--//
		ES_Talents_Main:SetParent(f)
		ES_Talents_Main:SetPoint("BOTTOM", f, "BOTTOM", 0, 5)
		ES_Talents_Main:Show()
		firstOpen = false
	end
end

function ES_Talents_TerminateProcess()
	if pendingIdx then
		ESTAL_Pending:Hide()
		pendingIdx = false
		table.wipe(pendingTalents)
		ES_ToggleAnimation("hide")
	end
end

ESTAL_Pending:RegisterEvent("ACTIVE_PLAYER_SPECIALIZATION_CHANGED")
local function ES_Talents_SpecChange()
	if firstOpen then
		ES_Talents_InitFunc()
	else
		local spcID = PlayerUtil.GetCurrentSpecID()
		local _, name = GetSpecializationInfoByID(spcID)		
		-- Populate DB if spec is missing, and update selection dropdown
		if not ESTAL_DB["auto"][spcID] then ESTAL_DB["auto"][spcID] = {} end
		if not ESTAL_DB["builds"][spcID] then ESTAL_DB["builds"][spcID] = {} end
		local pn = getPlayerName()
		local sel = ESTAL_DB["player"][pn]["selected"][spcID]
		if not sel then
			ESTAL_DB["player"][pn]["selected"][spcID] = false
			ES_Talents_Main.AutoDD:SetDefaultText("No selection")
		else
			ES_Talents_Main.AutoDD:SetDefaultText(sel)
		end
		if not ESTAL_DB["auto"][spcID][sel] then
			ESTAL_DB["player"][pn]["selected"][spcID] = false
			ES_Talents_Main.AutoDD:SetDefaultText("No selection")
		end
		--//
	end
	updateSpecBorder()
end
ESTAL_Pending:SetScript("OnEvent", ES_Talents_SpecChange)

-- Workaround to make sure the frame has been loaded before running initializing function
hooksecurefunc(_G["PlayerSpellsFrame"], "Show", function()
	ES_Talents_InitFunc()
end)

-- Need to catch situation where user closes frame before the build is finished loading
hooksecurefunc(_G["PlayerSpellsFrame"], "Hide", function()
	ES_Talents_TerminateProcess()
end)