@bootstrapParser
module lang::rascalcore::check::RascalConfig

extend lang::rascalcore::check::CheckerCommon;

 
extend lang::rascalcore::check::ADTandGrammar;

import lang::rascal::\syntax::Rascal;
import lang::rascalcore::compile::muRascal::AST;

import Location;

//extend lang::rascalcore::grammar::ParserGenerator;

import IO;
import List;
import Map;
import Set;
import Relation;
import String;

str parserPackage = "org.rascalmpl.core.library.lang.rascalcore.grammar.tests.generated_parsers";

// Define the name overloading that is allowed
bool rascalMayOverload(set[loc] defs, map[loc, Define] defines){
    bool seenVAR = false;
    bool seenNT  = false;
    bool seenLEX = false;
    bool seenLAY = false;
    bool seenKEY = false;
    bool seenALIAS = false;
    
    for(def <- defs){
        // Forbid:
        // - overloading of variables/formals
        // - overloading of incompatible syntax definitions
        switch(defines[def].idRole){
        case variableId(): 
            { if(seenVAR) return false;  seenVAR = true;}
        case formalId(): 
            { if(seenVAR) return false;  seenVAR = true;}
        case patternVariableId(): 
            { if(seenVAR) return false;  seenVAR = true;}
        case nonterminalId():
            { if(seenLEX || seenLAY || seenKEY){  return false; } seenNT = true; }
        case lexicalId():
            { if(seenNT || seenLAY || seenKEY) {  return false; } seenLEX= true; }
        case layoutId():
            { if(seenNT || seenLEX || seenKEY) {  return false; } seenLAY = true; }
        case keywordId():
            { if(seenNT || seenLAY || seenLEX) {  return false; } seenKEY = true; }
        case aliasId():
            { if(seenALIAS) return false; seenALIAS = true; } 
        }
    }
    return true;
}

// Name resolution filters

set[IdRole] defBeforeUseRoles = {variableId(), formalId(), keywordFormalId(), patternVariableId()};

@memo{expireAfter(minutes=15)}
Accept rascalIsAcceptableSimple(loc def, Use use, Solver s){
    //println("rascalIsAcceptableSimple: *** <use.id> *** def=<def>, use=<use>");
 
    if(isBefore(use.occ, def) &&                        // If we encounter a use before def
       !isEmpty(use.idRoles & defBeforeUseRoles) &&     // in an idRole that requires def before use
       isContainedIn(def, use.scope)){                  // and the definition is in the same scope as the use
    
      // then only allow this when inside explicitly defined areas (typically the result part of a comprehension)
                  
      if(lrel[loc,loc] allowedParts := s.getStack(key_allow_use_before_def)){
         list[loc] parts = allowedParts[use.scope];
         return !isEmpty(parts) && any(part <- parts, isContainedIn(use.occ, part)) ? acceptBinding() : ignoreContinue();
       } else {
            throw "Inconsistent value stored for <key_allow_use_before_def>: <s.getStack(key_allow_use_before_def)>";
       }
    }
    Define d = s.getDefine(def);
    // Uses of a keyword formal inside its initializing expression are rejected
    if(d.idRole == keywordFormalId() && isContainedIn(use.occ, d.defined)){
        return ignoreContinue();
    }
    return  acceptBinding();
}

Accept rascalIsAcceptableQualified(loc def, Use use, Solver s){
    // println("rascalIsAcceptableQualified: <def>, <use>");
    atype = s.getType(def);
       
    defPath = def.path;
    qualAsPath = replaceAll(use.ids[0], "::", "/") + ".rsc";
        
    // qualifier and proposed definition are the same?
    if(endsWith(defPath, qualAsPath)){
       return acceptBinding();
    }
        
    // Qualifier is a ADT name?
        
    if(acons(aadt(adtName, _, _), list[AType] _fields, list[Keyword] _kwFields) := atype){
       return  use.ids[0] == adtName ? acceptBinding() : ignoreContinue();
    }
    
    // Qualifier is a Production?
   
    if(aprod(prod(aadt(adtName, _, _), list[AType] _atypes)) := atype){
       return  use.ids[0] == adtName ? acceptBinding() : ignoreContinue();
    }
     
    // Is there another acceptable qualifier via an extend?
        
    extendedStarBy = {<to.path, from.path> | <loc from, extendPath(), loc to> <- s.getPaths()}*;
 
    if(!isEmpty(extendedStarBy) && any(p <- extendedStarBy[defPath]?{}, endsWith(p, defPath))){
       return acceptBinding();
    }
       
    return ignoreContinue();
}

Accept rascalIsAcceptablePath(loc _defScope, loc def, Use _use, PathRole pathRole, Solver s) {
    if(pathRole == importPath()){
        the_define = s.getDefine(def);
        defIdRole = the_define.idRole;
        // Only data declarations, constructors and visible entities are visible
        if(!(defIdRole == dataId() || defIdRole == constructorId() || the_define.defInfo.vis == publicVis())){
            return ignoreContinue();   
        }
    }
    
    return acceptBinding();
}

//alias Bindings = map[str varName, AType varType];

AType rascalInstantiateTypeParameters(Tree selector,
                                      def:aadt(str adtName1, list[AType] formals, SyntaxRole syntaxRole1),
                                      ins:aadt(str adtName2, list[AType] actuals, SyntaxRole syntaxRole2),
                                      AType act,
                                      Solver s){ 
    nformals = size(formals);
    nactuals = size(actuals);
    if(nformals != nactuals) s.report(error(selector, "Expected %v type parameters for %q, found %v", nformals, adtName1, nactuals));
    if(nformals > 0){
        if(adtName1 != adtName2) throw TypePalUsage("rascalInstantiateTypeParameters: <adtName1> versus <adtName2>");
        bindings = (formals[i].pname : actuals [i] | int i <- index(formals));
        return xxInstantiateRascalTypeParameters(selector, act, bindings, s);
    } else {
        return act;
    }
    //return visit(act) { case aparameter(str pname, AType bound):
    //                        if(asubtype(bindings[pname], bound)) insert bindings[pname]; else s.report(error(selector, "Type parameter %q should be less than %t, found %t", pname, bound, bindings[pname]));
    //                  };
}

default AType rascalInstantiateTypeParameters(Tree selector, AType formalType, AType actualType, AType toBeInstantiated, Solver s)
    = toBeInstantiated;
    
    
//AType xxInstantiateRascalTypeParameters(Tree selector, AType t, Bindings bindings, Solver s){
//    if(isEmpty(bindings))
//        return t;
//    else
//        return visit(t) { case param:aparameter(str pname, AType bound):
//                                if(asubtype(bindings[pname], bound)){
//                                    insert param.alabel? ? bindings[pname][alabel=param.alabel] :  bindings[pname];
//                               }
//                                else 
//                                    s.report(error(selector, "Type parameter %q should be less than %t, found %t", pname, bound, bindings[pname]));
//                        };
//}

default AType rascalInstantiateTypeParameters(Tree selector, AType def, AType ins, AType act, Solver s) = act;

tuple[list[str] typeNames, set[IdRole] idRoles] rascalGetTypeNamesAndRole(aprod(AProduction p)){
    return <[getADTName(p.def), "Tree"], {dataId(), nonterminalId(), lexicalId(), layoutId(), keywordId()}>;
}

tuple[list[str] typeNames, set[IdRole] idRoles] rascalGetTypeNamesAndRole(aadt(str adtName, list[AType] parameters, SyntaxRole syntaxRole)){
    return <isConcreteSyntaxRole(syntaxRole) ? [adtName, "Tree"] : [adtName], {dataId(), nonterminalId(), lexicalId(), layoutId(), keywordId()}>;
}

tuple[list[str] typeNames, set[IdRole] idRoles] rascalGetTypeNamesAndRole(acons(aadt(str adtName, list[AType] parameters, SyntaxRole syntaxRole), _, _)){
    return <[adtName], {dataId(), nonterminalId(), lexicalId(), layoutId(), keywordId()}>;
}

default tuple[list[str] typeNames, set[IdRole] idRoles] rascalGetTypeNamesAndRole(AType t){
    return <[], {}>;
}

AType rascalGetTypeInTypeFromDefine(Define containerDef, str selectorName, set[IdRole] idRolesSel, Solver s){
    //println("rascalGetTypeInTypeFromDefine: <containerDef>, <selectorName>");
    //println("commonKeywordFields: <containerDef.defInfo.commonKeywordFields>");
    containerType = s.getType(containerDef.defined);
    if(fieldId() in idRolesSel && selectorName == "top" && isStartNonTerminalType(containerType)){
        return getStartNonTerminalType(containerType);
    }
    
    for(kwf <- containerDef.defInfo.commonKeywordFields){
        if(prettyPrintName(kwf.name) == selectorName){
            return s.getType(kwf.\type);
        }
    }
    throw NoBinding();
}

AType rascalGetTypeInNamelessType(AType containerType, Tree selector, loc scope, Solver s){
    //println("rascalGetTypeInNamelessType: <containerType>, <selector>, <scope>");
    return computeFieldType(containerType, selector, scope, s);
}

bool rascalIsInferrable(IdRole idRole) = idRole in inferrableRoles;

loc findContainer(loc def, map[loc,Define] definitions, map[loc,loc] _scope){
    sc = definitions[def].scope;
    while(definitions[sc]? ? definitions[sc].idRole notin {functionId(), moduleId(), dataId(), constructorId()} : true){
        sc = definitions[sc].scope;
    }
    return sc;
}

bool isOverloadedFunction(loc fun, map[loc,Define] definitions, map[loc, AType] facts){
    fundef = definitions[fun];
    funid = fundef.id;
    funtype = facts[fun];
    for(loc l <- definitions, l != fun, Define def := definitions[l], def.id == funid, def.idRole == functionId()){
        if(comparable(facts[l], funtype)) return true;
    }
    return false;
}

bool rascalReportUnused(loc def, TModel tm){

    config = tm.config;
    if(!config.warnUnused) return false;
     
    definitions = tm.definitions;
    
    if(!definitions[def]? || !tm.moduleLocs[tm.modelName]?) return false;
    
    if(!isContainedIn(definitions[def].defined, tm.moduleLocs[tm.modelName])){
        return false;
    }
    
    scopes = tm.scopes;
    facts = tm.facts;
    
    bool reportFormal(Define define){
       if(!config.warnUnusedFormals || isWildCard(define.id[0])) return false;
       container = tm.definitions[findContainer(def, definitions, scopes)];
       if(container.idRole == functionId()){
          if(isOverloadedFunction(container.defined, definitions, facts)) return false;
          return  "java" notin container.defInfo.modifiers;
       }
       return false;
    }
    
    define = definitions[def];
    try {
        switch(define.idRole){
            case moduleId():            return false;
            case dataId():              return false;
            case functionId():          { if(isClosureName(define.id)) return false;
                                          if("test" in define.defInfo.modifiers) return false;
                                          if(define.defInfo.vis == privateVis()) return true;
                                          container = definitions[findContainer(def, definitions, scopes)];
                                          return container.idRole == functionId() && "java" notin container.defInfo.modifiers;
                                        }
            case constructorId():       return false;
            case fieldId():             return false;
            case keywordFieldId():      return false;
            case formalId():            return reportFormal(define); 
            case nestedFormalId():      return reportFormal(define); 
            case keywordFormalId():     return reportFormal(define); 
                                        
            case patternVariableId():   { if(!config.warnUnusedVariables) return false;
                                          return !isWildCard(define.id[0]);
                                        }
            case typeVarId():           return false;
            case variableId():          { if(!config.warnUnusedVariables) return false;
                                          container = definitions[findContainer(def, definitions, scopes)];
                                          if(container.idRole == moduleId() && define.defInfo.vis == publicVis()) return false;
                                          return isWildCard(define.id[0]) || define.id == "it";
                                        }
            case annoId():              return false;
            case aliasId():             return false;
            case lexicalId():           return false;
            case nonterminalId():       return false;
            case layoutId():            return false;
            case keywordId():           return false;
        }
    } catch NoSuchKey(_): return false;
    
    return true;
}

// Enhance TModel before running Solver by adding transitive edges for extend
TModel rascalPreSolver(map[str,Tree] _namedTrees, TModel m){
    extendPlus = {<from, to> | <loc from, extendPath(), loc to> <- m.paths}+;
    m.paths += { <from, extendPath(), to> | <loc from, loc to> <- extendPlus};
    m.paths += { <c, importPath(), a> | < loc c, importPath(), loc b> <- m.paths,  <b , extendPath(), loc a> <- m.paths};
    return m;
}

void checkOverloading(map[str,Tree] namedTrees, Solver s){
    if(s.reportedErrors()) return;
    
    set[Define] defines = s.getAllDefines();
    facts = s.getFacts();
    moduleScopes = { t@\loc | t <- range(namedTrees) };
    
    funDefs = {<define.id, define> | define <- defines, define.idRole == functionId() };
    funIds = domain(funDefs);
    for(id <- funIds){
        defs = funDefs[id];
        if(size(defs) > 1){
            for(d1 <- defs, d2 <- defs, d1.defined != d2.defined, 
                   t1 := facts[d1.defined]?afunc(avoid(),[],[]),
                   t2 := facts[d2.defined]?afunc(avoid(),[],[]),
                   d1.scope in moduleScopes, d2.scope in moduleScopes, size(t1.formals) == size(t2.formals)
                   ){
                if(t1.ret == avoid() && t2.ret != avoid()){
                    msgs = [ error("Declaration clashes with other declaration of function `<id>` with <facts[d1.defined].ret == avoid() ? "non-`void`" : "`void`"> result type at <d2.defined>", d1.defined) ];
                    s.addMessages(msgs);
                }
            }
            for(d1 <- defs, d2 <- defs, d1 != d2, 
                   t1 := facts[d1.defined]?afunc(avoid(),[],[]), 
                   t2 := facts[d2.defined]?afunc(avoid(),[],[]), 
                   (d1.scope in moduleScopes && d2.scope in moduleScopes && comparable(t1.formals, t2.formals))) {  
                 if(t1.kwFormals<0> != t2.kwFormals<0>){     
                    diffkws = t2.kwFormals<0> - t1.kwFormals<0>;  
                    plural = size(diffkws) > 1 ? "s" : "";
                    msgs = [ error("Declaration clashes with other declaration of function `<id>` with different keyword parameter<plural> <intercalate(",", [ "`<k.alabel>`" | k <- diffkws])> at <d2.defined>", d1.defined) ];
                    s.addMessages(msgs);
                  }
            }
            if(any(d1 <- defs, d2 <- defs, d1 != d2, 
                   t1 := facts[d1.defined]?afunc(avoid(),[],[]), 
                   t2 := facts[d2.defined]?afunc(avoid(),[],[]), 
                   d1.scope == d2.scope, 
                   (t1 has isTest && t1.isTest) || (t2 has isTest && t2.isTest))){
                msgs = [ error("Test name `<id>` should not be overloaded", d.defined) | d <- defs ];
                s.addMessages(msgs);
            }    
        }    
    }
    
    consNameDef = {<define.id, define> | define <- defines, define.idRole == constructorId() };
    consIds = domain(consNameDef);
    for(id <- consIds){
        defs = consNameDef[id];
        if(size(defs) > 0 && any(d1 <- defs, d2 <- defs, d1.defined != d2.defined, 
                                t1 := facts[d1.defined]?acons(aadt("***DUMMY***", [], dataSyntax()),[],[]),
                                t2 := facts[d2.defined]?acons(aadt("***DUMMY***", [], dataSyntax()),[],[]),
                                d1.scope in moduleScopes && d2.scope in moduleScopes && comparable(t1.fields, t2.fields),
                                ! (isSyntaxType(t1) && isSyntaxType(t2))
                                )){
            msgs = [ info("Constructor `<id>` overlaps with other declaration with comparable fields, on use add a qualifier", d.defined) | d <- defs ];
            s.addMessages(msgs);
        }      
    }
    try {
        matchingConds = [ <d, t, t.adt> | <_, Define d> <- consNameDef, d.scope in moduleScopes, t := s.getType(d)];
        for(<Define d1, AType t1, same_adt> <- matchingConds, <Define d2, AType t2, same_adt> <- matchingConds, d1.defined != d2.defined){
            for(fld1 <- t1.fields, fld2 <- t2.fields, fld1.alabel == fld2.alabel, !isEmpty(fld1.alabel), !comparable(fld1, fld2)){
                msgs = [ info("Field `<fld1.alabel>` is declared with different types in constructors `<d1.id>` and `<d2.id>` for `<t1.adt.adtName>`", d1.defined)
                       ];
                s.addMessages(msgs);
            }
        }
    } catch _: {
        // Guard against type incorrect defines, but record for now
        println("Skipping (type-incorrect) defines while checking duplicate labels in constructors");
    }
}

void rascalPostSolver(map[str,Tree] namedTrees, Solver s){
    
    if(!s.reportedErrors()){
       checkOverloading(namedTrees, s);
    
        for(_mname <- namedTrees){
            addADTsAndCommonKeywordFields(s);
        }
   }
}

TypePalConfig rascalTypePalConfig(bool classicReifier      = true,  
                                  bool logSolverIterations = false,
                                  bool logSolverSteps      = false,
                                  bool logAttempts         = false,
                                  bool logImports          = false
                                 )
    = tconfig(
        logTime                       = false,
        logSolverIterations           = logSolverIterations,
        logSolverSteps                = logSolverSteps,
        logAttempts                   = logAttempts,
        logImports                    = logImports,
        validateConstraints           = true,
        
        warnUnused                    = true,
        warnUnusedFormals             = true,
        warnUnusedVariables           = true,
        warnUnusedPatternFormals      = true,
        warnDeprecated                = false,
        
        getMinAType                   = AType(){ return avoid(); },
        getMaxAType                   = AType(){ return avalue(); },
        isSubType                     = /*lang::rascalcore::check::AType::*/asubtype,
        getLub                        = /*lang::rascalcore::check::AType::*/alub,
        
        isInferrable                  = rascalIsInferrable,
        isAcceptableSimple            = rascalIsAcceptableSimple,
        isAcceptableQualified         = rascalIsAcceptableQualified,
        isAcceptablePath              = rascalIsAcceptablePath,
        
        mayOverload                   = rascalMayOverload,       
        classicReifier                = classicReifier,
      
        getTypeNamesAndRole           = rascalGetTypeNamesAndRole,
        getTypeInTypeFromDefine       = rascalGetTypeInTypeFromDefine,
        getTypeInNamelessType         = rascalGetTypeInNamelessType,
        instantiateTypeParameters     = rascalInstantiateTypeParameters,
        
        preSolver                     = rascalPreSolver,
        postSolver                    = rascalPostSolver,
        reportUnused                  = rascalReportUnused
    );
