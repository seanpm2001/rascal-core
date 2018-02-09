module lang::rascalcore::check::TypePalConfig

extend analysis::typepal::TypePal;
extend analysis::typepal::TestFramework;
import analysis::typepal::ScopeGraph;

import analysis::typepal::TypePalConfig;

import lang::rascalcore::check::AType;
import List;
import Set;
import String;

data IdRole
    = moduleId()
    | functionId()
    | labelId()
    | constructorId()
    | fieldId()
    | dataId()
    | aliasId()
    | annoId()
    | nonterminalId()
    | lexicalId()
    | layoutId()
    | keywordId()
    ;

public set[IdRole] syntaxIds = {aliasId(), nonterminalId(), lexicalId(), layoutId(), keywordId()};
public set[IdRole] dataOrSyntaxIds = {dataId()} + syntaxIds;
public set[IdRole] dataIds = {aliasId(), dataId()}; 

data PathRole
    = importPath()
    | extendPath()
    ;
    
data ScopeRole
    = moduleScope()
    | functionScope()
    | conditionalScope()
    | replacementScope()
    | visitOrSwitchScope()
    | boolScope()
    | loopScope()
    ;

data Vis
    = publicVis()
    | privateVis()
    | defaultVis()
    ;

data Modifier
    = javaModifier()
    | testModifier()
    | defaultModifier()
    ;

// Visibility information
data DefInfo(Vis vis = publicVis());

// Productions and Constructor fields; common Keyword fields
data DefInfo(set[AProduction] productions = {}, 
             set[NamedField] constructorFields = {},
             set[AType] constructors = {},
             list[Keyword] commonKeywordFields = []
             );

// Maintain excluded use in parts of a scope
private str key_exclude_use = "exclude_use";

void storeExcludeUse(Tree cond, Tree excludedPart, TBuilder tb){
    tb.push(key_exclude_use, <getLoc(cond), getLoc(excludedPart)>);
}

// Maintain allow before use: where variables may be used left (before) their definition
private str key_allow_use_before_def = "allow_use_before_def";

void storeAllowUseBeforeDef(Tree container, Tree allowedPart, TBuilder tb){
    tb.push(key_allow_use_before_def, <getLoc(container), getLoc(allowedPart)>);
}

bool noOther(list[IdRole] forbidden, list[IdRole] roles)
    = isEmpty(forbidden & roles);
    
// Define the name overloading that is allowed
bool myMayOverload(set[Key] defs, map[Key, Define] defines){
    bool seenVAR = false;
    bool seenNT  = false;
    bool seenLEX = false;
    bool seenLAY = false;
    bool seenKEY = false;
    
    for(def <- defs){
        switch(defines[def].idRole){
        case variableId(): 
            { if(seenVar) return false;  seenVAR = true;}
        case nonterminalId():
            { if(seenLEX || seenLAY || seenKEY) return false; seenNT = true; }
        case lexicalId():
            { if(seenNT || seenLAY || seenKEY) return false;  seenLEX= true; }
        case layoutId():
            { if(seenNT || seenLEX || seenKEY) return false;  seenLAY = true; }
        case keywordId():
            { if(seenNT || seenLAY || seenLEX) return false;  seenKEY = true; }
        }
    }
    
    return true;
    
    idRoles = [defines[def].idRole | def <- defs];
   
    res = (  !([variableId(), variableId()] < idRoles)
          && nonterminalId() in idRoles   ==> noOther([lexicalId(), layoutId(), keywordId()], idRoles)
          && lexicalId()     in idRoles   ==> noOther([nonterminalId(), layoutId(), keywordId()], idRoles)
          && layoutId()      in idRoles   ==> noOther([nonterminalId(), lexicalId(), keywordId()], idRoles)
          && keywordId()     in idRoles   ==> noOther([nonterminalId(), lexicalId(), layoutId()], idRoles)
          );
           
    //res =    idRoles <= {functionId(), constructorId(), fieldId(), dataId(), annoId(), moduleId(), aliasId(), variableId()}
    //       || idRoles <= {dataId(), moduleId(), nonterminalId()} 
    //       || idRoles <= {dataId(), moduleId(), lexicalId()} 
    //       || idRoles <= {dataId(), moduleId(), layoutId()} 
    //       || idRoles <= {dataId(), moduleId(), keywordId()} 
    //       || idRoles <= {fieldId()}
    //       || idRoles <= {annoId()}
    //       ;
    
    if(!res) { println("myMayOverload <idRoles> ==\> <res>"); }
    return res;
}

// Name resolution filters
@memo
Accept isAcceptableSimple(TModel tm, Key def, Use use){
    //println("isAcceptableSimple: <use.id> def=<def>, use=<use>");
 
    if(variableId() in use.idRoles){
       // enforce definition before use
       if(def.path == use.occ.path && /*def.path == use.scope.path &&*/ def < use.scope){
          if(use.occ.offset < def.offset){
             // allow when inside explicitly use before def parts
             if(lrel[Key,Key] allowedParts := tm.store[key_allow_use_before_def] ? []){
                 list[Key] parts = allowedParts[use.scope];
                 if(!isEmpty(parts)){
                    if(any(part <- parts, use.occ < part)){
                       return acceptBinding();
                    }
                  } else {
                   //println("isAcceptableSimple =\> <ignoreContinue()>");
                   return ignoreContinue();
                 }
             } else {
                throw "Inconsistent value stored for <key_allow_use_before_def>: <tm.store[key_allow_use_before_def]>";
             }
          }
          // restrict when in excluded parts of a scope
          if(lrel[Key,Key] excludedParts := tm.store[key_exclude_use] ? []){
              list[Key] parts = excludedParts[use.scope];
              //println("parts = <parts>, <any(part <- parts, use.occ < part)>");
              if(!isEmpty(parts)){
                 if(any(part <- parts, use.occ < part)){
                    //println("isAcceptableSimple =\> <ignoreContinue()>");
                    return ignoreContinue();
                 }
              } 
          } else {
             throw "Inconsistent value stored for <key_allow_use_before_def>: <tm.store[key_allow_use_before_def]>";
          }
       }
    }
    //println("isAcceptableSimple =\> < acceptBinding()>");
    return  acceptBinding();
}

Accept isAcceptableQualified(TModel tm, Key def, Use use){
    //println("isAcceptableQualified: <def>, <use>");
    if(defType(AType atype) := tm.definitions[def].defInfo){
       
        defPath = def.path;
        qualAsPath = replaceAll(use.ids[0], "::", "/") + ".rsc";
        
        // qualifier and proposed definition are the same?
        if(endsWith(defPath, qualAsPath)){
           return acceptBinding();
        }
        
         // Qualifier is a ADT name?
        //if(acons(ret:aadt(adtName, list[AType] parameters, _), str consName, list[NamedField] fields, list[Keyword] kwFields) := atype, use.ids[0] == adtName){
        //    return acceptBinding();
        //} 
        
        if(acons(ret:aadt(adtName, list[AType] parameters, _), str consName, list[NamedField] fields, list[Keyword] kwFields) := atype){
           return  use.ids[0] == adtName ? acceptBinding() : ignoreContinue();
        } 
        
        // Is there another acceptable qualifier via an extend?
        
        extendedStarBy = {<to.path, from.path> | <Key from, extendPath(), Key to> <- tm.paths}*;
 
        if(!isEmpty(extendedStarBy) && any(p <- extendedStarBy[defPath]?{}, endsWith(p, defPath))){
           return acceptBinding();
        }
       
        return ignoreContinue();
    }
    return acceptBinding();
}

Accept isAcceptablePath(TModel tm, Key defScope, Key def, Use use, PathRole pathRole) {
    //println("isAcceptablePath <use.id>, candidate <def>, <pathRole>, <use>");
    //iprintln(tm.definitions[def]);
    res = acceptBinding();
    vis = tm.definitions[def].defInfo.vis;
    //println("vis: <vis>");
    if(pathRole == importPath()){
        defIdRole = tm.definitions[def].idRole;
        //println("defIfRole: <defIdRole>");
        //iprintln(tm.paths);
        //println("TEST: <<use.scope, importPath(), defScope> in tm.paths>");
        res = (defIdRole == dataId() || defIdRole == constructorId()) // data declarations and constructors are globally visible
              || //(<use.scope, importPath(), defScope> in tm.paths // one step import only
                  //&& 
                  vis == publicVis()
              ? acceptBinding() 
              : ignoreContinue();
    } else
    if(pathRole == extendPath()){
        res = acceptBinding();
    }
    //println("isAcceptablePath =\> <res>");
    return res;
}

data TypePalConfig(
    bool classicReifier = false
);

TypePalConfig rascalTypePalConfig(bool classicReifier = false)
    = tconfig(
        getMinAType                   = AType (){ return avoid(); },
        getMaxAType                   = AType (){ return avalue(); },
        isSubType                     = lang::rascalcore::check::AType::asubtype,
        getLub                        = lang::rascalcore::check::AType::alub,
        
        lookup                        = analysis::typepal::ScopeGraph::lookupWide,
       
        isAcceptableSimple            = isAcceptableSimple,
        isAcceptableQualified         = isAcceptableQualified,
        isAcceptablePath              = isAcceptablePath,
        
        mayOverload                   = myMayOverload,
        
        classicReifier                = classicReifier
        
    );
