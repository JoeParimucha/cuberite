
-- main.lua

-- Implements the plugin entrypoint (in this case the entire plugin)





-- Global variables:
g_Plugin = nil;
g_PluginFolder = "";






function Initialize(Plugin)
	g_Plugin = Plugin;
	
	Plugin:SetName("APIDump");
	Plugin:SetVersion(1);
	
	LOG("Initialized " .. Plugin:GetName() .. " v." .. Plugin:GetVersion())
	
	g_PluginFolder = Plugin:GetLocalFolder();

	-- dump all available API functions and objects:
	-- DumpAPITxt();
	
	-- Dump all available API object in HTML format into a subfolder:
	DumpAPIHtml();
	
	return true
end





function DumpAPITxt()
	LOG("Dumping all available functions to API.txt...");
	function dump (prefix, a, Output)
		for i, v in pairs (a) do
			if (type(v) == "table") then
				if (GetChar(i, 1) ~= ".") then
					if (v == _G) then
						-- LOG(prefix .. i .. " == _G, CYCLE, ignoring");
					elseif (v == _G.package) then
						-- LOG(prefix .. i .. " == _G.package, ignoring");
					else
						dump(prefix .. i .. ".", v, Output)
					end
				end
			elseif (type(v) == "function") then
				if (string.sub(i, 1, 2) ~= "__") then
					table.insert(Output, prefix .. i .. "()");
				end
			end
		end
	end

	local Output = {};
	dump("", _G, Output);

	table.sort(Output);
	local f = io.open("API.txt", "w");
	for i, n in ipairs(Output) do
		f:write(n, "\n");
	end
	f:close();
	LOG("API.txt written.");
end





function CreateAPITables()
	--[[
	We want an API table of the following shape:
	local API = {
		{
			Name = "cCuboid",
			Functions = {
				{Name = "Sort"},
				{Name = "IsInside"}
			},
			Constants = {
			}
			Descendants = {},  -- Will be filled by ReadDescriptions(), array of class APIs (references to other member in the tree)
		}},
		{
			Name = "cBlockArea",
			Functions = {
				{Name = "Clear"},
				{Name = "CopyFrom"},
				...
			}
			Constants = {
				{Name = "baTypes", Value = 0},
				{Name = "baMetas", Value = 1},
				...
			}
			...
		}}
	};
	local Globals = {
		Functions = {
			...
		},
		Constants = {
			...
		}
	};
	--]]

	local Globals = {Functions = {}, Constants = {}, Descendants = {}};
	local API = {};
	
	local function Add(a_APIContainer, a_ObjName, a_ObjValue)
		if (type(a_ObjValue) == "function") then
			table.insert(a_APIContainer.Functions, {Name = a_ObjName});
		elseif (
			(type(a_ObjValue) == "number") or
			(type(a_ObjValue) == "string")
		) then
			table.insert(a_APIContainer.Constants, {Name = a_ObjName, Value = a_ObjValue});
		end
	end
	
	local function ParseClass(a_ClassName, a_ClassObj)
		local res = {Name = a_ClassName, Functions = {}, Constants = {}, Descendants = {}};
		for i, v in pairs(a_ClassObj) do
			Add(res, i, v);
		end
		return res;
	end
	
	for i, v in pairs(_G) do
		if (
			(v ~= _G) and           -- don't want the global namespace
			(v ~= _G.packages) and  -- don't want any packages
			(v ~= _G[".get"]) and
			(v ~= g_APIDesc)
		) then
			if (type(v) == "table") then
				table.insert(API, ParseClass(i, v));
			else
				Add(Globals, i, v);
			end
		end
	end
	
	return API, Globals;
end





function DumpAPIHtml()
	LOG("Dumping all available functions and constants to API subfolder...");

	local API, Globals = CreateAPITables();
	local Hooks = {};
	local UndocumentedHooks = {};
	
	-- Sort the classes by name:
	table.sort(API,
		function (c1, c2)
			return (string.lower(c1.Name) < string.lower(c2.Name));
		end
	);
	
	-- Add Globals into the API:
	Globals.Name = "Globals";
	table.insert(API, Globals);
	
	-- Extract hook constants:
	for name, obj in pairs(cPluginManager) do
		if (type(obj) == "number") and (name:match("HOOK_.*")) then
			table.insert(Hooks, { Name = name });
		end
	end
	table.sort(Hooks,
		function(Hook1, Hook2)
			return (Hook1.Name < Hook2.Name);
		end
	);
	
	-- Read in the descriptions:
	ReadDescriptions(API);
	ReadHooks(Hooks);
	
	-- Create the output folder
	if not(cFile:IsFolder("API")) then
		cFile:CreateFolder("API");
	end

	-- Create a "class index" file, write each class as a link to that file,
	-- then dump class contents into class-specific file
	local f = io.open("API/index.html", "w");
	if (f == nil) then
		LOGINFO("Cannot output HTML API: " .. err);
		return;
	end
	
	f:write([[<html><head><title>MCServer API - index</title>
	<link rel="stylesheet" type="text/css" href="main.css" />
	</head><body><h1>MCServer API - index</h1>
	<p>The API reference is divided into the following sections:<ul>
		<li><a href="#classes">Class index</a></li>
		<li><a href="#hooks">Hooks</a></li>
		<li><a href="#extra">Extra pages</a></li>
	</ul></p>
	<a name="classes"><h2>Class index</h2></a>
	<p>The following classes are available in the MCServer Lua scripting language:
	<ul>
	]]);
	for i, cls in ipairs(API) do
		f:write("<li><a href=\"" .. cls.Name .. ".html\">" .. cls.Name .. "</a></li>\n");
		WriteHtmlClass(cls, API);
	end
	f:write([[</ul></p>
	<a name="hooks"><h2>Hooks</h2></a>
	<p>A plugin can register to be called whenever an �interesting event� occurs. It does so by calling
	<a href="cPluginManager.html">cPluginManager</a>'s AddHook() function and implementing a callback
	function to handle the event.</p>
	<p>A plugin can decide whether it will let the event pass through to the rest of the plugins, or hide it
	from them. This is determined by the return value from the hook callback function. If the function returns
	false or no value, the event is propagated further. If the function returns true, the processing is
	stopped, no other plugin receives the notification (and possibly MCServer disables the default behavior
	for the event). See each hook's details to see the exact behavior.</p>
	<table><tr><th>Hook name</th><th>Called when</th></tr>
	]]);
	for i, hook in ipairs(Hooks) do
		if (hook.DefaultFnName == nil) then
			-- The hook is not documented yet
			f:write("<tr><td>" .. hook.Name .. "</td><td><i>(No documentation yet)</i></td></tr>\n");
			table.insert(UndocumentedHooks, hook.Name);
		else
			f:write("<tr><td><a href=\"" .. hook.DefaultFnName .. ".html\">" .. hook.Name .. "</a></td><td>" .. LinkifyString(hook.CalledWhen) .. "</td></tr>\n");
			WriteHtmlHook(hook);
		end
	end
	f:write([[</table>
	<a name="extra"><h2>Extra pages</h2></a>
	<p>The following pages provide various extra information</p>
	<ul>]]);
	for i, extra in ipairs(g_APIDesc.ExtraPages) do
		local SrcFileName = g_PluginFolder .. "/" .. extra.FileName;
		if (cFile:Exists(SrcFileName)) then
			local DstFileName = "API/" .. extra.FileName;
			if (cFile:Exists(DstFileName)) then
				cFile:Delete(DstFileName);
			end
			cFile:Copy(SrcFileName, DstFileName);
			f:write("<li><a href=\"" .. extra.FileName .. "\">" .. extra.Title .. "</a></li>\n");
		else
			f:write("<li>" .. extra.Title .. " <i>(file is missing)</i></li>\n");
		end
	end
	f:write([[</ul>
	</body></html>
	]]);
	f:close();
	
	-- Copy the CSS file to the output folder (overwrite any existing):
	cssf = io.open("API/main.css", "w");
	if (cssf ~= nil) then
		cssfi = io.open(g_Plugin:GetLocalDirectory() .. "/main.css", "r");
		if (cssfi ~= nil) then
			local CSS = cssfi:read("*all");
			cssf:write(CSS);
			cssfi:close();
		end
		cssf:close();
	end
	
	-- List the undocumented objects:
	f = io.open("API/undocumented.lua", "w");
	if (f ~= nil) then
		f:write("\n-- This is the list of undocumented API objects, automatically generated by APIDump\n\n");
		f:write("g_APIDesc =\n{\n\tClasses =\n\t{\n");
		for i, cls in ipairs(API) do
			local HasFunctions = ((cls.UndocumentedFunctions ~= nil) and (#cls.UndocumentedFunctions > 0));
			local HasConstants = ((cls.UndocumentedConstants ~= nil) and (#cls.UndocumentedConstants > 0));
			if (HasFunctions or HasConstants) then
				f:write("\t\t" .. cls.Name .. " =\n\t\t{\n");
				if ((cls.Desc == nil) or (cls.Desc == "")) then
					f:write("\t\t\tDesc = \"\"\n");
				end
			end
			
			if (HasFunctions) then
				f:write("\t\t\tFunctions =\n\t\t\t{\n");
				table.sort(cls.UndocumentedFunctions);
				for j, fn in ipairs(cls.UndocumentedFunctions) do
					f:write("\t\t\t\t" .. fn .. " = { Params = \"\", Return = \"\", Notes = \"\" },\n");
				end  -- for j, fn - cls.Undocumented[]
				f:write("\t\t\t},\n\n");
			end
			
			if (HasConstants) then
				f:write("\t\t\tConstants =\n\t\t\t{\n");
				table.sort(cls.UndocumentedConstants);
				for j, cn in ipairs(cls.UndocumentedConstants) do
					f:write("\t\t\t\t" .. cn .. " = { Notes = \"\" },\n");
				end  -- for j, fn - cls.Undocumented[]
				f:write("\t\t\t},\n\n");
			end
			
			if (HasFunctions or HasConstants) then
				f:write("\t\t},\n\n");
			end
		end  -- for i, cls - API[]
		f:write("\t},\n");
		
		if (#UndocumentedHooks > 0) then
			f:write("\n\tHooks =\n\t{\n");
			for i, hook in ipairs(UndocumentedHooks) do
				if (i > 1) then
					f:write("\n");
				end
				f:write("\t\t" .. hook .. " =\n\t\t{\n");
				f:write("\t\t\tCalledWhen = \"\",\n");
				f:write("\t\t\tDefaultFnName = \"On\",  -- also used as pagename\n");
				f:write("\t\t\tDesc = [[]],\n");
				f:write("\t\t\tParams =\n\t\t\t{\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t\t{ Name = \"\", Type = \"\", Notes = \"\" },\n");
				f:write("\t\t\t},\n");
				f:write("\t\t\tReturns = [[]],\n");
				f:write("\t\t},  -- " .. hook .. "\n");
			end
		end
		f:close();
	end
	
	-- List the unexported documented API objects:
	f = io.open("API/unexported-documented.txt", "w");
	if (f ~= nil) then
		for clsname, cls in pairs(g_APIDesc.Classes) do
			if not(cls.IsExported) then
				-- The whole class is not exported
				f:write("class\t" .. clsname .. "\n");
			else
				if (cls.Functions ~= nil) then
					for fnname, fnapi in pairs(cls.Functions) do
						if not(fnapi.IsExported) then
							f:write("func\t" .. clsname .. "." .. fnname .. "\n");
						end
					end  -- for j, fn - cls.Functions[]
				end
				if (cls.Constants ~= nil) then
					for cnname, cnapi in pairs(cls.Constants) do
						if not(cnapi.IsExported) then
							f:write("const\t" .. clsname .. "." .. cnname .. "\n");
						end
					end  -- for j, fn - cls.Functions[]
				end
			end
		end  -- for i, cls - g_APIDesc.Classes[]
		f:close();
	end
	
	LOG("API subfolder written");
end





function ReadDescriptions(a_API)
	-- Returns true if the class of the specified name is to be ignored
	local function IsClassIgnored(a_ClsName)
		if (g_APIDesc.IgnoreClasses == nil) then
			return false;
		end
		for i, name in ipairs(g_APIDesc.IgnoreClasses) do
			if (a_ClsName:match(name)) then
				return true;
			end
		end
		return false;
	end
	
	-- Returns true if the function (specified by its fully qualified name) is to be ignored
	local function IsFunctionIgnored(a_FnName)
		if (g_APIDesc.IgnoreFunctions == nil) then
			return false;
		end
		for i, name in ipairs(g_APIDesc.IgnoreFunctions) do
			if (a_FnName:match(name)) then
				return true;
			end
		end
		return false;
	end
	
	-- Returns true if the constant (specified by its fully qualified name) is to be ignored
	local function IsConstantIgnored(a_CnName)
		if (g_APIDesc.IgnoreConstants == nil) then
			return false;
		end;
		for i, name in ipairs(g_APIDesc.IgnoreConstants) do
			if (a_CnName:match(name)) then
				return true;
			end
		end
		return false;
	end
	
	-- Remove ignored classes from a_API:
	local APICopy = {};
	for i, cls in ipairs(a_API) do
		if not(IsClassIgnored(cls.Name)) then
			table.insert(APICopy, cls);
		end
	end
	for i = 1, #a_API do
		a_API[i] = APICopy[i];
	end;

	-- Process the documentation for each class:
	for i, cls in ipairs(a_API) do
		-- Rename special functions:
		for j, fn in ipairs(cls.Functions) do
			if (fn.Name == ".call") then
				fn.DocID = "constructor";
				fn.Name = "() <i>(constructor)</i>";
			elseif (fn.Name == ".add") then
				fn.DocID = "operator_plus";
				fn.Name = "<i>operator +</i>";
			elseif (fn.Name == ".div") then
				fn.DocID = "operator_div";
				fn.Name = "<i>operator /</i>";
			elseif (fn.Name == ".mul") then
				fn.DocID = "operator_mul";
				fn.Name = "<i>operator *</i>";
			elseif (fn.Name == ".sub") then
				fn.DocID = "operator_sub";
				fn.Name = "<i>operator -</i>";
			elseif (fn.Name == ".eq") then
				fn.DocID = "operator_eq";
				fn.Name = "<i>operator ==</i>";
			end
		end
		
		local APIDesc = g_APIDesc.Classes[cls.Name];
		if (APIDesc ~= nil) then
			APIDesc.IsExported = true;
			cls.Desc = APIDesc.Desc;
			cls.AdditionalInfo = APIDesc.AdditionalInfo;
			
			-- Process inheritance:
			if (APIDesc.Inherits ~= nil) then
				for j, icls in ipairs(a_API) do
					if (icls.Name == APIDesc.Inherits) then
						table.insert(icls.Descendants, cls);
						cls.Inherits = icls;
					end
				end
			end

			cls.UndocumentedFunctions = {};  -- This will contain names of all the functions that are not documented
			cls.UndocumentedConstants = {};  -- This will contain names of all the constants that are not documented
			
			local DoxyFunctions = {};  -- This will contain all the API functions together with their documentation
			
			local function AddFunction(a_Name, a_Params, a_Return, a_Notes)
				table.insert(DoxyFunctions, {Name = a_Name, Params = a_Params, Return = a_Return, Notes = a_Notes});
			end
			
			if (APIDesc.Functions ~= nil) then
				-- Assign function descriptions:
				for j, func in ipairs(cls.Functions) do
					local FnName = func.DocID or func.Name;
					local FnDesc = APIDesc.Functions[FnName];
					if (FnDesc == nil) then
						-- No description for this API function
						AddFunction(func.Name);
						if not(IsFunctionIgnored(cls.Name .. "." .. FnName)) then
							table.insert(cls.UndocumentedFunctions, FnName);
						end
					else
						-- Description is available
						if (FnDesc[1] == nil) then
							-- Single function definition
							AddFunction(func.Name, FnDesc.Params, FnDesc.Return, FnDesc.Notes);
						else
							-- Multiple function overloads
							for k, desc in ipairs(FnDesc) do
								AddFunction(func.Name, desc.Params, desc.Return, desc.Notes);
							end  -- for k, desc - FnDesc[]
						end
						FnDesc.IsExported = true;
					end
				end  -- for j, func
				
				-- Replace functions with their described and overload-expanded versions:
				cls.Functions = DoxyFunctions;
			end  -- if (APIDesc.Functions ~= nil)
			
			if (APIDesc.Constants ~= nil) then
				-- Assign constant descriptions:
				for j, cons in ipairs(cls.Constants) do
					local CnDesc = APIDesc.Constants[cons.Name];
					if (CnDesc == nil) then
						-- Not documented
						if not(IsConstantIgnored(cls.Name .. "." .. cons.Name)) then
							table.insert(cls.UndocumentedConstants, cons.Name);
						end
					else
						cons.Notes = CnDesc.Notes;
						CnDesc.IsExported = true;
					end
				end  -- for j, cons
			end  -- if (APIDesc.Constants ~= nil)
		else
			-- Class is not documented at all, add all its members to Undocumented lists:
			cls.UndocumentedFunctions = {};
			cls.UndocumentedConstants = {};
			for j, func in ipairs(cls.Functions) do
				local FnName = func.DocID or func.Name;
				if not(IsFunctionIgnored(cls.Name .. "." .. FnName)) then
					table.insert(cls.UndocumentedFunctions, FnName);
				end
			end  -- for j, func - cls.Functions[]
			for j, cons in ipairs(cls.Constants) do
				if not(IsConstantIgnored(cls.Name .. "." .. cons.Name)) then
					table.insert(cls.UndocumentedConstants, cons.Name);
				end
			end  -- for j, cons - cls.Constants[]
		end  -- else if (APIDesc ~= nil)
		
		-- Remove ignored functions:
		local NewFunctions = {};
		for j, fn in ipairs(cls.Functions) do
			if (not(IsFunctionIgnored(cls.Name .. "." .. fn.Name))) then
				table.insert(NewFunctions, fn);
			end
		end  -- for j, fn
		cls.Functions = NewFunctions;

		-- Sort the functions (they may have been renamed):
		table.sort(cls.Functions,
			function(f1, f2)
				if (f1.Name == f2.Name) then
					-- Same name, either comparing the same function to itself, or two overloads, in which case compare the params
					if ((f1.Params == nil) or (f2.Params == nil)) then
						return 0;
					end
					return (f1.Params < f2.Params);
				end
				return (f1.Name < f2.Name);
			end
		);
		
		-- Sort the constants:
		table.sort(cls.Constants,
			function(c1, c2)
				return (c1.Name < c2.Name);
			end
		);
	end  -- for i, cls
	
	-- Sort the descendants lists:
	for i, cls in ipairs(a_API) do
		table.sort(cls.Descendants,
			function(c1, c2)
				return (c1.Name < c2.Name);
			end
		);
	end  -- for i, cls
end





function ReadHooks(a_Hooks)
	--[[
	a_Hooks = {
		{ Name = "HOOK_1"},
		{ Name = "HOOK_2"},
		...
	};
	We want to add hook descriptions to each hook in this array
	--]]
	for i, hook in ipairs(a_Hooks) do
		local HookDesc = g_APIDesc.Hooks[hook.Name];
		if (HookDesc ~= nil) then
			for key, val in pairs(HookDesc) do
				hook[key] = val;
			end
		end
	end  -- for i, hook - a_Hooks[]
end





-- Make a link out of anything with the special linkifying syntax {{link|title}}
function LinkifyString(a_String)
	local txt = a_String:gsub("{{([^|}]*)|([^}]*)}}", "<a href=\"%1.html\">%2</a>")  -- {{link|title}}
	txt = txt:gsub("{{([^|}]*)}}", "<a href=\"%1.html\">%1</a>")  -- {{LinkAndTitle}}
	return txt;
end





function WriteHtmlClass(a_ClassAPI, a_AllAPI)
	local cf, err = io.open("API/" .. a_ClassAPI.Name .. ".html", "w");
	if (cf == nil) then
		return;
	end
	
	-- Writes a table containing all functions in the specified list, with an optional "inherited from" header when a_InheritedName is valid
	local function WriteFunctions(a_Functions, a_InheritedName)
		if (#a_Functions == 0) then
			return;
		end

		if (a_InheritedName ~= nil) then
			cf:write("<h2>Functions inherited from " .. a_InheritedName .. "</h2>");
		end
		cf:write("<table><tr><th>Name</th><th>Parameters</th><th>Return value</th><th>Notes</th></tr>\n");
		for i, func in ipairs(a_Functions) do
			cf:write("<tr><td>" .. func.Name .. "</td>");
			cf:write("<td>" .. LinkifyString(func.Params or "").. "</td>");
			cf:write("<td>" .. LinkifyString(func.Return or "").. "</td>");
			cf:write("<td>" .. LinkifyString(func.Notes or "") .. "</td></tr>\n");
		end
		cf:write("</table>\n");
	end
	
	local function WriteDescendants(a_Descendants)
		if (#a_Descendants == 0) then
			return;
		end
		cf:write("<ul>");
		for i, desc in ipairs(a_Descendants) do
			cf:write("<li><a href=\"".. desc.Name .. ".html\">" .. desc.Name .. "</a>");
			WriteDescendants(desc.Descendants);
			cf:write("</li>\n");
		end
		cf:write("</ul>\n");
	end

	-- Build an array of inherited classes chain:
	local InheritanceChain = {};
	local CurrInheritance = a_ClassAPI.Inherits;
	while (CurrInheritance ~= nil) do
		table.insert(InheritanceChain, CurrInheritance);
		CurrInheritance = CurrInheritance.Inherits;
	end
	
	cf:write([[<html><head><title>MCServer API - ]] .. a_ClassAPI.Name .. [[ class</title>
	<link rel="stylesheet" type="text/css" href="main.css" />
	<script src="https://google-code-prettify.googlecode.com/svn/loader/run_prettify.js"></script>
	<script src="http://google-code-prettify.googlecode.com/svn/trunk/src/lang-lua.js"></script>
	</head><body>
	<h1>Contents</h1>
	<ul>
	]]);
	
	local HasInheritance = ((#a_ClassAPI.Descendants > 0) or (a_ClassAPI.Inherits ~= nil));
	
	-- Write the table of contents:
	if (HasInheritance) then
		cf:write("<li><a href=\"#inherits\">Inheritance</a></li>\n");
	end
	cf:write("<li><a href=\"#constants\">Constants</a></li>\n");
	cf:write("<li><a href=\"#functions\">Functions</a></li>\n");
	if (a_ClassAPI.AdditionalInfo ~= nil) then
		for i, additional in ipairs(a_ClassAPI.AdditionalInfo) do
			cf:write("<li><a href=\"#additionalinfo_" .. i .. "\">" .. additional.Header .. "</a></li>\n");
		end
	end
	cf:write("</ul>");
	
	-- Write the class description:
	cf:write("<a name=\"desc\"><h1>" .. a_ClassAPI.Name .. " class</h1></a>\n");
	if (a_ClassAPI.Desc ~= nil) then
		cf:write("<p>");
		cf:write(LinkifyString(a_ClassAPI.Desc));
		cf:write("</p>\n");
	end;
	
	-- Write the inheritance, if available:
	if (HasInheritance) then
		cf:write("<a name=\"inherits\"><h1>Inheritance</h1></a>\n");
		if (#InheritanceChain > 0) then
			cf:write("<p>This class inherits from the following parent classes:<ul>\n");
			for i, cls in ipairs(InheritanceChain) do
				cf:write("<li><a href=\"" .. cls.Name .. ".html\">" .. cls.Name .. "</a></li>\n");
			end
			cf:write("</ul></p>\n");
		end
		if (#a_ClassAPI.Descendants > 0) then
			cf:write("<p>This class has the following descendants:\n");
			WriteDescendants(a_ClassAPI.Descendants);
			cf:write("</p>\n");
		end
	end
	
	-- Write the constants:
	cf:write("<a name=\"constants\"><h1>Constants</h1></a>\n");
	cf:write("<table><tr><th>Name</th><th>Value</th><th>Notes</th></tr>\n");
	for i, cons in ipairs(a_ClassAPI.Constants) do
		cf:write("<tr><td>" .. cons.Name .. "</td>");
		cf:write("<td>" .. cons.Value .. "</td>");
		cf:write("<td>" .. LinkifyString(cons.Notes or "") .. "</td></tr>\n");
	end
	cf:write("</table>\n");
	
	-- Write the functions, including the inherited ones:
	cf:write("<a name=\"functions\"><h1>Functions</h1></a>\n");
	WriteFunctions(a_ClassAPI.Functions, nil);
	for i, cls in ipairs(InheritanceChain) do
		WriteFunctions(cls.Functions, cls.Name);
	end
	
	-- Write the additional infos:
	if (a_ClassAPI.AdditionalInfo ~= nil) then
		for i, additional in ipairs(a_ClassAPI.AdditionalInfo) do
			cf:write("<a name=\"additionalinfo_" .. i .. "\"><h1>" .. additional.Header .. "</h1></a>\n");
			cf:write(LinkifyString(additional.Contents));
		end
	end

	cf:write("</body></html>");
	cf:close();
end





function WriteHtmlHook(a_Hook)
	local fnam = "API/" .. a_Hook.DefaultFnName .. ".html";
	local f, error = io.open(fnam, "w");
	if (f == nil) then
		LOG("Cannot write \"" .. fnam .. "\": \"" .. error .. "\".");
		return;
	end
	f:write([[<html><head><title>MCServer API - ]] .. a_Hook.DefaultFnName .. [[ hook</title>
	<link rel="stylesheet" type="text/css" href="main.css" />
	<script src="https://google-code-prettify.googlecode.com/svn/loader/run_prettify.js"></script>
	<script src="http://google-code-prettify.googlecode.com/svn/trunk/src/lang-lua.js"></script>
	</head><body>
	<h1>]] .. a_Hook.Name .. [[ hook</h1>
	<p>
	]]);
	f:write(LinkifyString(a_Hook.Desc));
	f:write("</p><h1>Callback function</h1><p>The default name for the callback function is ");
	f:write(a_Hook.DefaultFnName .. ". It has the following signature:");
	f:write("<pre class=\"prettyprint lang-lua\">function " .. a_Hook.DefaultFnName .. "(");
	if (a_Hook.Params == nil) then
		a_Hook.Params = {};
	end
	for i, param in ipairs(a_Hook.Params) do
		if (i > 1) then
			f:write(", ");
		end
		f:write(param.Name);
	end
	f:write(")</pre><p>Parameters:\n<table><tr><th>Name</th><th>Type</th><th>Notes</th></tr>\n");
	for i, param in ipairs(a_Hook.Params) do
		f:write("<tr><td>" .. param.Name .. "</td><td>" .. LinkifyString(param.Type) .. "</td><td>" .. LinkifyString(param.Notes) .. "</td></tr>\n");
	end
	f:write("</table></p>\n<p>" .. (a_Hook.Returns or "") .. "</p>\n");
	f:write([[<h1>Code examples</h1>
	<h2>Registering the callback</h2>
<pre class=\"prettyprint lang-lua\">
cPluginManager.AddHook(cPluginManager.]] .. a_Hook.Name .. ", My" .. a_Hook.DefaultFnName .. [[);
</pre>
	]]);
	local Examples = a_Hook.CodeExamples or {};
	for i, example in ipairs(Examples) do
		f:write("<h2>" .. example.Title .. "</h2>\n");
		f:write("<p>" .. example.Desc .. "</p>\n");
		f:write("<pre class=\"prettyprint lang-lua\">" .. example.Code .. "</pre>\n");
	end
	f:close();
end




