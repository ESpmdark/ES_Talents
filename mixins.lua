ESTalentMainMixin = {}
function ESTalentMainMixin:OnLoad()
	self.AcceptButton:SetEnabled(false)
	self.Title:SetText(self.titleText)
	self.exclusive = true;
	self.AcceptButton:SetOnClickHandler(GenerateClosure(self.OnAccept, self));
	self.CancelButton:SetOnClickHandler(GenerateClosure(self.OnCancel, self));

	if self.NameControl then self.NameControl:GetEditBox():SetAutoFocus(false); end
	if self.ImportControl then self.ImportControl:GetEditBox():SetAutoFocus(false); end
	
	if self:GetName() == "ES_Talents_Manager" then
		self.AcceptButton:SetText("Save")
	end
end

function ESTalentMainMixin:OnHide()
	if self:GetName() == "ES_Talents_Manager" then
		local f = self.Count:SetText("0/2000 Characters Used")
	end
end

function ESTalentMainMixin:OnCancel()
	if self:GetName() == "ES_Talents_Import" then
		self.CheckButton:SetChecked(false)
		self.CheckButton.Text:SetText("Save build directly from import string")
		self.NameControl:Hide()
		self.Title:SetText("Import talents from loadout")
		self.AcceptButton:SetText("Import")
	end
	self:Hide()
end

function ESTalentMainMixin:OnAccept()
	if self.AcceptButton:IsEnabled() then
		local success
		if self:GetName() == "ES_Talents_Save" then
			local loadoutName = self.NameControl:GetText();
			success = ES_Talents_SaveDialog(loadoutName)
		elseif self:GetName() == "ES_Talents_Import" then
			local importText = self.ImportControl:GetText();
			local loadoutName = self.NameControl:GetText();
			if self.CheckButton:GetChecked() then
				success = ES_Talents_SaveDialog(loadoutName, importText)
			else
				success = ES_Talents_ImportBuild(importText)
			end
		else
			local importText = self.ImportControl:GetText();
			local loadoutName = self.NameControl:GetText();
			success = ES_Talents_Manager_Save(loadoutName, importText);
		end
		if success then
			if self:GetName() == "ES_Talents_Import" then
				self.CheckButton:SetChecked(false)
				self.CheckButton.Text:SetText("Save build directly from import string")
				self.NameControl:Hide()
				self.Title:SetText("Import talents from loadout")
				self.AcceptButton:SetText("Import")
			end
			self:Hide()
		end
	end
end

function ESTalentMainMixin:UpdateAcceptButtonEnabledState()
	local importTextFilled = self.ImportControl and self.ImportControl:HasText();
	local nameTextFilled = self.NameControl:HasText();
	local result = false
	if self:GetName() == "ES_Talents_Save"  then
		result = nameTextFilled
	elseif self:GetName() == "ES_Talents_Import" then
		if self.CheckButton:GetChecked() then
			result = (importTextFilled and nameTextFilled)
		else
			result = importTextFilled
		end
	else
		result = (importTextFilled and nameTextFilled)
	end
	self.AcceptButton:SetEnabled(result);
end

function ESTalentMainMixin:OnTextChanged()
	self:UpdateAcceptButtonEnabledState();
end

ESTalentsEditBoxMixin = CreateFromMixins(ClassTalentLoadoutDialogInputControlMixin);

function ESTalentsEditBoxMixin:OnTextChanged()
	self:GetParent():OnTextChanged();
	if self:GetParent():GetName() == "ES_Talents_Manager" then
		local f = self:GetParent().ImportControl
		if f and f:GetEditBox():HasFocus() then
			self:GetParent().Count:SetText(self:GetEditBox():GetNumLetters() .. "/2000 Characters Used")
		end
	end
	InputScrollFrame_OnTextChanged(self.InputContainer.EditBox);
end

function ESTalentsEditBoxMixin:GetEditBox()
	return self.InputContainer.EditBox;
end

function ESTalentsEditBoxMixin:OnEnterPressed()
	local f = self:GetParent().ImportControl
	if f and f:GetEditBox():HasFocus() then
		self:GetEditBox():Insert('\n')
	end
end