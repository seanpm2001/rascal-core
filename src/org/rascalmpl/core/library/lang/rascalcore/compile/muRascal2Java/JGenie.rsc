module lang::rascalcore::compile::muRascal2Java::JGenie

import lang::rascal::\syntax::Rascal;

import List;
import Set;
import IO;
import String;
import Map;
import lang::rascalcore::compile::muRascal::AST;
import lang::rascalcore::compile::muRascal2Java::CodeGen;
import lang::rascalcore::compile::util::Names;
import lang::rascalcore::compile::Rascal2muRascal::TypeUtils;

import lang::rascalcore::compile::muRascal2Java::Conversions;

import lang::rascalcore::check::AType;
import lang::rascalcore::check::ATypeUtils;
import lang::rascalcore::check::BasicRascalConfig;

alias JCode = str;

data JGenie
    = jgenie(
        str () getModuleName,
        loc () getModuleLoc,
        void (MuFunction) setFunction,
        MuFunction () getFunction,
        str () getFunctionName,
        bool (MuExp) isDefinedInCurrentFunction,
        AType (loc src) getType,
        str (loc src) getAccessor,
        str (loc src) getAccessorInResolver,
        Define (loc src) getDefine,
        list[MuExp] (loc src) getExternalVars,
        void(str name) setKwpDefaults,
        str() getKwpDefaults,
        str(AType atype) shareType,
        str(value con) shareConstant,
        str(AType, map[AType,set[AType]]) shareATypeConstant,
        str () getConstants,
        bool (str con) isWildCard,
        void(list[MuExp] evars) addExternalVars,
        bool (MuExp exp) isExternalVar,
        str(str prefix) newTmp,
        void(str) addImportedLibrary,
        list[str] () getImportedLibraries,
        void (tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads) addResolver,
        bool (tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads) isResolved,
        bool (tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads) usesLocalFunctions
      )
    ;
    
JGenie makeJGenie(str moduleName, map[str,TModel] tmodels, map[str,loc] moduleLocs, map[str, MuFunction] muFunctions){
    str kwpDefaults = "$kwpDefaults";
    map[value,str] constants = ();
    map[str,value] constant2value = ();
    map[AType,str] types = ();
    int nconstants = -1;
    int ntypes = -1;
    
    map[AType,str] atype_constants = ();
    map[AType,map[AType,set[AType]]] atype_definitions = ();
    map[str,AType] atype_constant2atype = ();
    int ntconstants = -1;
    
    set[MuExp] externalVars = {};
    int ntmps = -1;
    set[str] importedLibraries = {};
    
    TModel currentModule = tmodels[moduleName];
    loc currentModuleScope = moduleLocs[moduleName];
    set[tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors]] resolvers = {};
    str functionName = "$UNKNOWN";
    MuFunction function;
    
    map[loc,list[MuExp]] fun2externals = (fun.src : fun.externalVars  | fun <- range(muFunctions));
    
    iprintln(fun2externals);
   
    str _getModuleName()
        = currentModule.modelName;
        
    loc _getModuleLoc()
        = currentModuleScope;
        
    void _setFunction(MuFunction fun){
        function = fun;
        qname = replaceAll(fun.qname, "::", "_");
        idx = findFirst(qname, "$CLOSURE");
        if(idx >= 0){
            functionName = qname[idx ..];
            idx = findFirst(functionName, "_");
            functionName = functionName[ .. idx];
        } else { 
            idx = findFirst(qname, "$");    // preserve $ as first characters (as oppsoed to separator with module name 
            functionName = idx > 0 ? qname[idx+1 .. ] : qname;
        }
    }
    
    MuFunction _getFunction()
        = function;
    
    str _getFunctionName()
        = functionName;
    
    AType _getType(loc src)
        = currentModule.facts[src];
        
    str getImportedModuleName(loc def){
        for(mname <- moduleLocs){
            if(containedIn(def, moduleLocs[mname])){
                return module2field(mname);
            }
        }
        throw "getImportedModuleName<def>";
    }
        
    str _getAccessor(loc src){
        for(mname <- tmodels){
            if(tmodels[mname].definitions[src]?){
                def = tmodels[mname].definitions[src];
                if(defType(AType tp) := def.defInfo){
                    descriptor = atype2idpart(tp);
                    baseName = getJavaName(def.id);
                    if(containedIn(def.defined, currentModuleScope)){
                        return startsWith(baseName, "$CLOSURE") ? baseName : "$me.<baseName>_<descriptor>";
                    } else {
                        return startsWith(baseName, "$CLOSURE") ? baseName : "<getImportedModuleName(def.defined)>.<baseName>_<descriptor>";
                    }
                 }
             }
        }
        //for(str fname <- muFunctions){
        //    if(muFunctions[fname].src == src){
        //        return fname;
        //    }
        //}
        throw "No accessor found for <src>";
    }
    
    str _getAccessorInResolver(loc src){
        for(mname <- tmodels){
            if(tmodels[mname].definitions[src]?){
                def = tmodels[mname].definitions[src];
                if(defType(AType tp) := def.defInfo){
                    baseName = "<getJavaName(def.id, completeId=false)>_<def.defined.begin.line>_<def.defined.end.line>";
                    if(containedIn(def.defined, currentModuleScope)){
                        return baseName;
                    } else {
                        return "<getImportedModuleName(src)>.<baseName>";
                    }
                 }
             }
        }
        throw "getAccessorInResolver <src>";
    }
    
    Define _getDefine(loc src){
        for(mname <- tmodels){
                if(tmodels[mname].definitions[src]?){
                    return tmodels[mname].definitions[src];
                }
        }
        throw "getDefine <src>";
    }
    
    list[MuExp] _getExternalVars(loc src){
        evars = containedIn(src, currentModuleScope) ? fun2externals[src] : [];
        return [var | var <- evars, var.pos >= 0 ];
    }
    
    bool _isDefinedInCurrentFunction(MuExp var){
        definitions = currentModule.definitions;
        for(d <- definitions, def := definitions[d], var.name == def.id, containedIn(def.scope, function.src), def.idRole in variableRoles){
            return true;
        }
        return false;
    }
    
    void _setKwpDefaults(str name){
        kwpDefaults = name;
    }
    
    str _getKwpDefaults() = kwpDefaults;
    
    str _shareType(AType atype){
        if(types[atype]?) return types[atype];
        ntypes += 1;
        c = "$T<ntypes>";
        types[atype] = c;
        return c;
    }
    
    str _shareConstant(value v){
        if(constants[v]?) return constants[v];
        nconstants += 1;
        c = "$C<nconstants>";
        constants[v] = c;
        constant2value[c] = v;
        return c;
    }
    
    str _shareATypeConstant(AType t, map[AType,set[AType]] definitions){
        if(atype_constants[t]?) return atype_constants[t];
        ntconstants += 1;
        c = "$R<ntconstants>";
        atype_constants[t] = c;
        atype_definitions[t] = definitions;
        atype_constant2atype[c] = t;
        return c;
    }
    
    str _getConstants(){
        return "<for(v <- constants){>
               'private static final <value2outertype(v)> <constants[v]> = <value2IValue(v)>;
               '<}>
               '<for(t <- types){>
               'private static final io.usethesource.vallang.type.Type <types[t]> = <atype2typestore(t)>;
               '<}>
               '<for(t <- atype_constants){>
               'private static final IConstructor <atype_constants[t]> = <atype2IValue(areified(t), atype_definitions[t])>;
               '<}>";
    }
    
    bool _isWildCard(str con){
        if(constant2value[con]?){
            return constant2value[con] == "_";
        }
        return false;
    }
    
    void _addExternalVars(list[MuExp] vars){
        externalVars += toSet(vars);
    }
    
    bool _isExternalVar(MuExp var) = var in externalVars;
    
    str _newTmp(str prefix){
        ntmps += 1;
        return "$<prefix><ntmps>";
    }
    
    void _addImportedLibrary(str lib){
        importedLibraries += lib;
    }
    
    list[str] _getImportedLibraries(){
        return toList(importedLibraries);
    }
    
    void _addResolver(tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads){
        resolvers += overloads;
    }
    bool _isResolved(tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads){
        return overloads in resolvers;
    }
    
    bool _usesLocalFunctions(tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overloads){
        return    any(of <- overloads.ofunctions, containedIn(currentModule.definitions[of].defined, currentModuleScope))
               || any(oc <- overloads.oconstructors, containedIn(currentModule.definitions[oc].defined, currentModuleScope));
    }
    
    return jgenie(
                _getModuleName,
                _getModuleLoc,
                _setFunction,
                _getFunction,
                _getFunctionName,
                _isDefinedInCurrentFunction,
                _getType,
                _getAccessor,
                _getAccessorInResolver,
                _getDefine,
                _getExternalVars,
                _setKwpDefaults,
                _getKwpDefaults,
                _shareType,
                _shareConstant,
                _shareATypeConstant,
                _getConstants,
                _isWildCard,
                _addExternalVars,
                _isExternalVar,
                _newTmp,
                _addImportedLibrary,
                _getImportedLibraries,
                _addResolver,
                _isResolved,
                _usesLocalFunctions
            );
}

// ---- casting ---------------------------------------------------------------

str castArg(AType t, str x) = startsWith(x, "((<atype2javatype(t)>)(") ? x : "(<atype2javatype(t)>)(<x>)";
str cast(AType t, str x) = "(<castArg(t,x)>)";