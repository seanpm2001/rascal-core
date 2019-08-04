module lang::rascalcore::compile::muRascal2Java::CodeGen

import lang::rascal::\syntax::Rascal;

import lang::rascalcore::compile::muRascal::AST;
import lang::rascalcore::check::AType;
import lang::rascalcore::check::ATypeUtils;
import lang::rascalcore::check::BasicRascalConfig;
import List;
import Set;
import Relation;
import String;
import Map;
import Node;
import IO;
import Type;
import util::Reflective;

//extend analysis::typepal::TypePal;

//extend lang::rascalcore::check::RascalConfig;

import lang::rascalcore::compile::muRascal2Java::Primitives;

import lang::rascalcore::compile::muRascal2Java::JGenie;
import lang::rascalcore::compile::muRascal2Java::Conversions;

import lang::rascalcore::compile::util::Names;

bool debug = false;

// ---- globals ---------------------------------------------------------------

map[str, MuFunction] muFunctions = ();
map[loc, MuFunction] muFunctionsByLoc = ();
map[str,str] resolved2overloaded = ();

// ---- muModule --------------------------------------------------------------

tuple[JCode, JCode, JCode] muRascal2Java(MuModule m, map[str,TModel] tmodels, map[str,loc] moduleLocs){
    muFunctions = (f.qname : f | f <- m.functions);
    muFunctionsByLoc = (f.src : f | f <- m.functions);
    resolved2overloaded = ();
    jg = makeJGenie(m.name, tmodels, moduleLocs, muFunctions);
    <typestore, kwpDecls> = generateTypeStoreAndKwpDecls(m.ADTs, m.constructors);
    <signatures, resolvers> = genResolvers(m.overloaded_functions, jg);
    
    bool hasMainFunction = false;
    str mainName = "main";
    AType mainType = avoid();
    MuFunction mainFunction;
    for(f <- m.functions){
        if(startsWith(f.qname, "main_")) {
            hasMainFunction = true;
            mainFunction = f;
            mainType = f.ftype;
            mainName = f.qname;
        }
        jg.addExternalVars(f.externalVars);
    }
    moduleName = m.name;
    className = getClassName(moduleName);    
    packageName = getPackageName(moduleName);
    interfaceName = "$<className>"; //module2interface(m.name);
    
    module_variables  = "<for(var <- m.module_variables){>
                        'static <trans(var, jg)><}>";
                       
    functions         = "<for(f <- m.functions){>
                        '<trans(f, jg)>
                        '<}>";
                       
    library_imports   = "";
                        //"<for(class <- jg.getImportedLibraries()){>
                        //'import <class>;
                        //'<}>";
                       
    library_inits     = "<for(class <- jg.getImportedLibraries()){>
                         'final <getQualClassName(class)> <getBaseClass(class)> = new <getQualClassName(class)>($VF);
                         '<}>";
                        
    module_extends    =  ""; //!isEmpty(m.extends) ? ", " + intercalate(", ",[ module2class(ext) | ext <- m.extends]) : "";
                        
    module_imports    = "<for(imp <- toSet(m.imports + m.extends), contains(module2class(imp), ".")){>
                         'import <module2class(imp)>;
                        '<}>";
                       
    imp_ext_decls     = "<for(imp <- toSet(m.imports + m.extends)){>
                        '<getClassRef(imp, moduleName)> <module2field(imp)>;
                        '<}>";
                           
    module_ext_inits  = "<for(ext <- m.extends){>
                        '<module2field(ext)> = <module2class(ext)>.extend<getBaseClass(ext)>(this);
                        '<}>";
    iprintln(m.initialization);
    class_constructor = "public <className>(){
                        '    this(new ModuleStore());
                        '}
                        '
                        'public <className>(ModuleStore store){
                        '   this.$me = this;
                        '   <for(imp <- m.imports, imp notin m.extends){>
                        '   <module2field(imp)> = store.importModule(<getClassRef(imp, moduleName)>.class, <getClassRef(imp, moduleName)>::new);
                        '   <}> 
                        '   <for(ext <- m.extends){>
                        '   <module2field(ext)> = new <getBaseClass(ext)>(store);
                        '   <}>
                        '   <kwpDecls>
                        '   <for(muVarInit(var, exp) <- m.initialization){><var.name> = <trans(exp, jg)>;
                        '   <}>
                        '}";
    externalArgs = "";                 
    if(hasMainFunction && !isEmpty(mainFunction.externalVars)){
      externalArgs = intercalate(", ", [ "new ValueRef\<<jtype>\>(<var.name>)" | var <- sort(mainFunction.externalVars), var.pos >= 0, jtype := atype2javatype(var.atype)]);
    }              
    main_method       = hasMainFunction ? (mainFunction.ftype.ret == avoid() ? "public static void main(String[] args) {
                                                                    'new <className>().<mainName>(<externalArgs>);
                                                                    '}"
                                                                  : "public static void main(String[] args) {
                                                                    'IValue res = new <className>().<mainName>(<externalArgs>); 
                                                                    'if(res == null) throw new RuntimeException(\"Main function failed\"); else System.out.println(res);
                                                                    '}")
                                        : "public static void main(String[] args) {
                                          'throw new RuntimeException(\"No function `main` found in Rascal program `<m.name>`\");
                                          '}";
    
    the_class =         "<if(!isEmpty(packageName)){>package <packageName>;<}>
                        'import java.util.*;
                        'import java.util.regex.Matcher;
                        'import io.usethesource.vallang.*;
                        'import io.usethesource.vallang.type.*;
                        'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.*;
                        'import org.rascalmpl.library.experiments.Compiler.RVM.Interpreter.RascalExecutionContext;
                        'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.function.*;
                        'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.traverse.*;
                        'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.utils.*;
                        'import org.rascalmpl.interpreter.result.util.MemoizationCache;
                        '
                        '<library_imports>
                        '<module_imports>
                        '
                        'public class <className> extends org.rascalmpl.core.library.lang.rascalcore.compile.runtime.$RascalModule implements <interfaceName> <module_extends> {
                        '    static final Traverse $TRAVERSE = new Traverse($VF);
                        '    private final <interfaceName> $me;
                        '    private RascalExecutionContext rex;
                        '    <typestore>
                        '    <library_inits>
                        '    <imp_ext_decls>
                        '    <module_variables>
                        '    <class_constructor>
                        '    <jg.getConstants()>
                        '    <resolvers>
                        '    <functions>
                        '    <main_method>
                        '}";
      
      the_interface =  "<if(!isEmpty(packageName)){>package <packageName>;<}>
                       'import java.util.*;
                       'import io.usethesource.vallang.*;
                       'import io.usethesource.vallang.type.*;
                       'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.ValueRef;
                       'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.function.*;
                       'public interface $<className> {
                       '    <signatures>
                       '}\n";
                       
      the_test_class = generateTestClass(packageName, className, m.functions, jg);
      
      return <the_interface, the_class, the_test_class>;
}

str generateTestClass(str packageName, str className, list[MuFunction] functions, JGenie jg){
    return "<if(!isEmpty(packageName)){>package <packageName>;<}>
           'import java.util.*;
           'import java.util.stream.Stream;
           'import io.usethesource.vallang.*;
           'import io.usethesource.vallang.type.*;
           '
           'import static org.junit.Assert.assertTrue;
           'import static org.junit.Assert.fail;
           'import static org.junit.jupiter.api.DynamicTest.dynamicTest;
           '
           'import org.junit.jupiter.api.Test;
           'import org.junit.Ignore;
           'import org.junit.jupiter.api.DynamicTest;
           'import org.junit.jupiter.api.TestFactory;
           'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.utils.*;
           'import org.rascalmpl.core.library.lang.rascalcore.compile.runtime.*;
           '
           'class <className>Test extends org.rascalmpl.core.library.lang.rascalcore.compile.runtime.$RascalModule {
           '    <className> $me;
           '    static final TypeFactory $TF = TypeFactory.getInstance();
           '    static final GenerateActuals generator = new GenerateActuals(5, 5, 10);
       
           '    public <className>Test(){
           '        ModuleStore store = new ModuleStore();
           '        $me = store.importModule(<className>.class, <className>::new);                       
           '    }
           '    <for(f <- functions){>
           '    <generateTestMethod(f, className, jg)><}>
           '}\n";
}

str generateTestMethod(MuFunction f, str className, JGenie jg){
    if("test" notin f.modifiers) return "";
    
    test_name = getJavaName(f.uqname);
    test_name_uniq = "<test_name>_<f.src.begin.line>";
    formals = f.ftype.formals;
    expected = f.tags["expected"] ? "";
    ignored = !isEmpty(domain(f.tags) & {"ignore", "Ignore", "ignoreCompiler", "IgnoreCompiler"});
    if(ignored){
        return "@Ignore
               'void <test_name_uniq>(){ }\n";
    }
    fun_name = jg.getAccessor(f.src); //"<test_name>_<f.src.begin.line>_<f.src.end.line>";
    
    externalArgs = "";                 
    if(!isEmpty(f.externalVars)){
      externalArgs = intercalate(", ", [ "new ValueRef\<<jtype>\>(<className>.<var.name>)" | var <- sort(f.externalVars), var.pos >= 0, jtype := atype2javatype(var.atype)]);
    }  
    if(isEmpty(formals)){
        if(isEmpty(expected)){
            return "@Test
                   'void <test_name_uniq>(){
                   '   assertTrue(<fun_name>(<externalArgs>).getValue());
                   '}\n";
        } else {
            return "@Test
                   'void <test_name_uniq>(){
                   '    try {
                   '        <fun_name>(<externalArgs>);
                   '    } catch (RascalException e) {
                   '        if(((IConstructor) e.getValue()).getConstructorType() == RascalExceptionFactory.<expected>) {
                   '            assertTrue(true);
                   '            return;
                   '         }
                   '         fail(\"Expected `<expected>`, got: \" + e);
                   '    }
                   '    fail(\"Expected `<expected>`, but nothing was thrown\");
                   '}\n";
        }
    }
    types = "new Type[] {<intercalate(", ", [atype2typestore(tp) | tp <- formals])>}";
    actuals = intercalate(", ", ["args[<i>]" | i <- index(formals)]) + ", Collections.emptyMap()";
    if(!isEmpty(externalArgs)){
        actuals += ", " + externalArgs;
    }
    if(isEmpty(expected)){
        return "@TestFactory
               'Stream\<DynamicTest\> <test_name_uniq>(){
               '    return generator.generateActuals(<types>).map((args) -\> dynamicTest(\"<test_name>\", () -\> assertTrue(((IBool)$me.<test_name>(<actuals>)).getValue())));
               '}\n";
     } else {
        return "@TestFactory
               'Stream\<DynamicTest\> <test_name_uniq>(){
               '    return generator.generateActuals(<types>).map((args) -\> dynamicTest(\"<test_name>\", () -\> {
               '        try {
               '            $me.<test_name>(<actuals>);
               '            fail(\"Expected `<expected>`, but nothing was thrown\");
               '        } catch (RascalException e) {
               '            if(((IConstructor) e.getValue()).getConstructorType() == RascalExceptionFactory.<expected>) {
               '               assertTrue(true);
               '               return;
               '            } else {
               '              fail(\"Expected `<expected>`, but got `\" + e + \"`\");
               '            }
               '        } catch (Exception e){
               '            fail(\"Expected `<expected>`, but got Java exception `\" + e + \"`\");
               '        }
               '    }));
               '}\n";
     }
}

tuple[str,str] generateTypeStoreAndKwpDecls(set[AType] ADTs, set[AType] constructors){
    adtDecls = "";
    seenAdtNames = {};
    for(aadt(str adtName, list[AType] parameters, SyntaxRole syntaxRole) <- ADTs){
        if(adtName notin seenAdtNames){
            adtDecls += "static final io.usethesource.vallang.type.Type <getADTName(adtName)> = $TF.abstractDataType($TS, \"<adtName>\");\n";
            seenAdtNames += adtName;
        }
    }
    consDecls = "";
    kwpDecls = "";
    map[str, set[AType]] kwpField2Cons = ();
    map[str, AType] kwpField2Type = ();
    for(c: acons(AType adt, list[AType] fields, list[Keyword] kwpFields) <- constructors){
        adt_cons = atype2idpart(c);
        fieldDecls = [ "<atype2typestore(fld)>, \"<fld.label>\"" | fld <- fields ];
        consDecls += "static final io.usethesource.vallang.type.Type <adt_cons> = $TF.constructor($TS, <getADTName(adt.adtName)>, \"<c.label>\"<isEmpty(fieldDecls) ? "" : ", <intercalate(", ", fieldDecls)>">);\n";
        for(kwpField <- kwpFields){
            kwpDecls += "$TS.declareKeywordParameter(<adt_cons>,\"<kwpField.fieldType.label>\", <atype2typestore(kwpField.fieldType)>);\n";
            fieldName = kwpField.fieldType.label;
            if(kwpField2Cons[fieldName]?){
                kwpField2Cons[fieldName] += {c};
                kwpField2Type[fieldName] =  alub(kwpField.fieldType, kwpField2Type[fieldName]);
            } else {
                kwpField2Cons[fieldName] = {c};
                kwpField2Type[fieldName] =  kwpField.fieldType;
           }
        }
    }
    consResolvers = "";
    
    for(kwpFieldName <-kwpField2Cons){
        consesWithField = kwpField2Cons[kwpFieldName];
       
        // find all ADTs that have this keyword field
        relevantADTs = { c.adt.adtName | AType c <- consesWithField };
       
        // ... and generate resolvers for th
        fieldType = avoid();
        code = "";
        for(adtName <- relevantADTs){
            kwpFieldType = kwpField2Type[kwpFieldName];
            for(c <- consesWithField){ 
                 if(c.adt.adtName == adtName){
                        code += "if($0.getConstructorType() == <atype2idpart(c)>){
                                '  return $get_<getJavaName(adtName, completeId=false)>_<c.label>_<kwpFieldName>($0);
                                '}\n";
                 }
            }
            getterName = "$get_<getJavaName(adtName, completeId=false)>_<kwpFieldName>";
            consResolvers += "<atype2javatype(kwpFieldType)> <getterName>(IConstructor $0){
                             '  <code>
                             '  throw new RuntimeException(\"<getterName> fails\");
                             '}\n";
        } 
    }
    
    return <"<adtDecls>
            '<consDecls>
            '
            '<consResolvers>
            '",
            kwpDecls>;
}

alias OF5 = tuple[str name, AType funType, str oname, list[loc] ofunctions, list[loc] oconstructors];
alias OF4 = tuple[AType funType, str oname, list[loc] ofunctions, list[loc] oconstructors];

bool larger(OF5 a, OF5 b){
   return a.name <= b.name &&
          size(a.ofunctions) + size(a.oconstructors) >
          size(b.ofunctions) + size(b.oconstructors);
}

list[OF5] sortOverloads(set[OF5] ofs){
    return sort(ofs, larger);
}

list[OF5] filterMostAlts(set[OF5] overloadedFunctions){
    sorted = sortOverloads(overloadedFunctions);
    int last = size(sorted) - 1;
    filtered = [ *((i == last || sorted[i].name != sorted[i+1].name || sorted[i].funType != sorted[i+1].funType) ? [sorted[i]] : []) | int i <- index(sorted)];
    return filtered;
}

tuple[str signatures, str methods] genResolvers(list[OF5] overloadedFunctions, JGenie jg){
    //overloadedFunctions = for(ovl <- overloadedFunctions) {  ovl.funType = unsetRec(ovl.funType); append ovl; }
    //println("genResolvers:"); iprintln(overloadedFunctions);
    moduleLoc = jg.getModuleLoc();
    overloadedFunctions1 = { overload | overload <- overloadedFunctions, 
                                        !startsWith(overload.oname, "$CLOSURE"), 
                                        any(of <- overload.ofunctions, containedIn(of, moduleLoc)) || any(oc <- overload.oconstructors, containedIn(oc, moduleLoc)) };
    mostAlts = filterMostAlts(overloadedFunctions1);
    all_signatures = ""; 
    all_resolvers = "";
    // For every function name + type, choose the one with the most alternatives
    fnames = toSet(mostAlts<0>);
 
    for(overload <- mostAlts){
        if(!resolved2overloaded[overload.oname]?) {
            //overloaded_versions += <fname, ftype, overload>;
            //println("add to resolved2overloaded: <overload.oname>, <overload.name>");
            resolved2overloaded[overload.oname] = overload.name;
            <signatures, resolvers> = genResolver(overload, jg);
            all_signatures += signatures;
            all_resolvers += resolvers;
        }
    }
  
    for(str fname <- fnames){
        <signatures, resolvers> = genGeneralResolver(fname, mostAlts[fname], jg);
        all_signatures += signatures;
        all_resolvers += resolvers;
    }
    return <all_signatures, all_resolvers>;
}

list[OF4] sortOverloads(list[OF4] overloads){
    return sort(overloads, bool(OF4 a, OF4 b){ return a.funType != b.funType && asubtype(b.funType, a.funType); });
}

tuple[str signatures, str resolvers] genGeneralResolver(str fname, list[OF4] overloads, JGenie jg){
    if(fname == "type" || startsWith(fname, "$CLOSURE")) return <"","">;
    //println("genGeneralResolver:"); iprintln(overloads);
    arities = { getArity(ovl.funType) | ovl <- overloads };
    all_signatures = "";
    all_resolvers = "";
    for(int i <- arities, i > 0){
        returns_void = true;
        cases = "";
        canFail = any(ovl <- overloads, ftype := ovl.funType, getArity(ftype) == i, any(of <- ovl.ofunctions, di := jg.getDefine(of).defInfo, di has canFail, di.canFail));
   
        externalVars = {};
        for(ovl <- sortOverloads(overloads), ftype := unsetRec(ovl.funType), getArity(ftype) == i){
            externalVars += {*jg.getExternalVars(ofun) | ofun <- ovl.ofunctions };
        }
        for(ovl <- sortOverloads(overloads), ftype := unsetRec(ovl.funType), getArity(ftype) == i){
           returns_void = returns_void && ftype has ret && (ftype.ret == avoid());
           formalTypes = getFormals(ftype);
           if(i > 0 && !all(formalType <- formalTypes, formalType == avalue())){
               argTypes = "<intercalate(", ", [ "(<atype2javatype(tf)>)$<j>"  | j <- index(formalTypes), tf := formalTypes[j]])>";
               if(hasKeywordParameters (ftype)) argTypes += ", $kwpActuals";
               if(!isEmpty(externalVars)){
                  argTypes += (isEmpty(argTypes) ? "" : ", ") + intercalate(", ", [ varName(var, jg) | var <- sort(externalVars), jtype := atype2javatype(var.atype)]);
               }
               base_call = "<getJavaName(fname, completeId=false)>_<atype2idpart(ftype)>(<argTypes>)";
               
               call_code = canFail ? ( returns_void ? "try { <base_call>; return; }
                                                      'catch (FailReturnFromVoidException e):{};\n"
                                                       
                                                    : "res = <base_call>;
                                                      'if(res != null) return <returns_void ? "" : "res">;\n"
                                     )
                                   : ( returns_void ? "<base_call>; return;\n"
                                                  
                                                    : "return <base_call>;\n"
                                     );
               //cases += "if(<intercalate(" && ", [ "$<j>.getType().<atype2istype(tf)>()"  | j <- index(formalTypes), tf := formalTypes[j]])>){
               cases += "if(<intercalate(" && ", [ atype2istype("$<j>", tf) | j <- index(formalTypes), tf := formalTypes[j]])>){
                        '   <call_code>
                        '}\n";
           }
        }
        sig_formals = "<intercalate(", ", ["IValue $<j>" | j <- [0..i] ])>, java.util.Map\<String,IValue\> $kwpActuals";
        if(!isEmpty(externalVars)){
                  sig_formals += ", " + intercalate(", ", [ "ValueRef\<<jtype>\> <varName(var, jg)>" | var <- sort(externalVars), jtype := atype2javatype(var.atype)]);
         }
        signature = "public <returns_void ? "void" : "IValue"> <getJavaName(fname)>(<sig_formals>)";
        all_signatures += signature + ";\n";
        all_resolvers += "<signature>{
                             '  <if(canFail && !returns_void){>IValue res;<}>
                             '  <cases>
                             '  throw new RuntimeException(\"Cannot resolve call to `<fname>`\");
                             '}\n";
    }
    return <all_signatures, all_resolvers>;
}

tuple[str signatures, str resolvers] genResolver(tuple[str name, AType funType, str scope, list[loc] ofunctions, list[loc] oconstructors] overload, JGenie jg){
   if(overload.name == "type") return <"","">;
   //println("genResolver:"); iprintln(overload);
   
   funType = unsetRec(overload.funType);
   returns_void = funType has ret && funType.ret == avoid();
   formalTypes = getFormals(funType);
   returnType = atype2javatype(getResult(funType));
   //if(getArity(funType) == 0){
   //     of = size(overload.ofunctions) > 0 ? overload.ofunctions[0] : overload.oconstructors[0];
   //     return <"public <returnType> <overload.name>();\n", 
   //             "public <returnType> <overload.name>() { return <jg.getAccessorInResolver(of)>(); }\n"
   //            >;
   //}
   if(jg.isResolved(overload) || !jg.usesLocalFunctions(overload) /*|| getArity(funType) == 0*/) return <"", "">;
 
   if(getArity(funType) != 0 && all(formalType <-formalTypes, formalType == avalue())) return <"", "">;
   
   jg.addResolver(overload);
  
   anyKwParams = any(ovl <- overload.ofunctions + overload.oconstructors, hasKeywordParameters(jg.getType(ovl)));
   
   concretePatterns = any(ovl <- overload.ofunctions /*+ overload.oconstructors*/, jg.getType(ovl).isConcreteArg);
  
   
   argTypes = intercalate(", ", ["<atype2javatype(f)> $<i>" | i <- index(formalTypes), f := formalTypes[i]]);
   if(anyKwParams){
        kwpActuals = "java.util.Map\<String,IValue\> $kwpActuals";
        argTypes = isEmpty(argTypes) ? kwpActuals : "<argTypes>, <kwpActuals>";
   }
   
   externalVars = {*jg.getExternalVars(ofun) | ofun <- overload.ofunctions };
   if(!isEmpty(externalVars)){
        argTypes += (isEmpty(formalTypes) ? "" : ", ") +  intercalate(", ", [ "ValueRef\<<jtype>\> <varName(var, jg)>" | var <- sort(externalVars), jtype := atype2javatype(var.atype)]);
   }
   
   name_resolver = "<replaceAll(overload.name, "::", "_")>_<atype2idpart(overload.funType)>";
   signature = "public <returnType> <getJavaName(name_resolver)>(<argTypes>)";
   canFail = any(of <- overload.ofunctions, di := jg.getDefine(of).defInfo, di has canFail, di.canFail);
   map[int,str] cases = ();
   for(of <- overload.ofunctions){
        fp = jg.getType(of).abstractFingerprint;
        if(cases[fp]?){
            cases[fp] += makeCall(funType, of, jg);
        } else {
            cases[fp] = makeCall(funType, of, jg);
        }
   }
   
   conses = "";
   for(of <- overload.oconstructors){
        conses += makeCall(funType, of, jg);
   }
     
   body = "";
   if(size(cases) == 1){
    for(c <- cases){
        body = cases[c];
        break;
    }
   } else if(size(cases) > 1){
   //   '             <if(!startsWith(split("\n", cases[caseLab])[-1], "return") && !contains(cases[caseLab], "break;")){> break;<}>
        body = "switch(ToplevelType.getFingerprint($0, <concretePatterns>)){
               '<for(caseLab <- cases, caseLab != 0){>
               '         case <caseLab>: { 
               '             <cases[caseLab]> 
               '             break;
               '         }
               '    <}>
               '        default: {
               '            <cases[0]>
               '        }
               '}";
   }
   
   return <signature + ";\n",
          "<signature>{
          '    <if(true /*canFail*/ && !returns_void){><atype2javatype(getResult(funType))> res;<}>
          '    <body>
          '    <conses>
          '    <if(true /*canFail*/ && isEmpty(conses)){>throw new RuntimeException(\"Cannot resolve call to `<name_resolver>`\");<}>
          '}
          '">;
}

JCode makeCall(AType resolverFunType, loc of, JGenie jg){
    funType = jg.getType(of);
    kwpActuals = "$kwpActuals";
    formalTypes = getFormals(funType);
    returns_void = funType has ret && funType.ret == avoid();
    resolverFormalTypes = getFormals(resolverFunType);
    if(any(int i <- index(formalTypes), unsetRec(formalTypes[i]) != unsetRec(resolverFormalTypes[i]))){
        conds = [];
        actuals = [];
        for(int i <- index(resolverFormalTypes)){
            if(unsetRec(formalTypes[i]) != resolverFormalTypes[i]){
                //conds +=  "$<i>.getType().<atype2istype(formalTypes[i])>()"; 
                conds +=  atype2istype("$<i>", formalTypes[i]);
                actuals += "(<atype2javatype(formalTypes[i])>) $<i>";
            } else {
                actuals += "$<i>";
                 //actuals += "<resolverFunType.formals[i].label>$<i>";
            }
        } 
        if(hasKeywordParameters(funType)){
            actuals = isEmpty(actuals) ? [kwpActuals] : actuals + kwpActuals;
        }
     
        base_call = "";
        if(isConstructorType(funType)){
            return "return <makeConstructorCall(funType, actuals, jg)>;";
        } else {
            externalVars = jg.getExternalVars(of);
            if(!isEmpty(externalVars)){
                argTypes += (isEmpty(formalTypes) ? "" : ", ") +  intercalate(", ", [ varName(var, jg) | var <- sort(externalVars), jtype := atype2javatype(var.atype)]);
             }
            call_code = "<jg.getAccessorInResolver(of)>(<intercalate(", ", actuals)>)";
            di = jg.getDefine(of).defInfo;
            returns_void = funType.ret == avoid();
            
            base_call = di has canFail && true /*di.canFail*/ ? (returns_void ? "try { <call_code>; return; } catch (FailReturnFromVoidException e){}\n"
                                                                     : "res = <call_code>;
                                                                       'if(res != null) return <returns_void ? "" : "res">;\n"
                                                       )
                                                       
                                                     : ( returns_void ? "<call_code>; return;\n"
                                                                      : "return <call_code>;\n"
                                                       );
        }
        if(isEmpty(conds)){
            return base_call;
        } else {
            return "if(<intercalate(" && ", conds)>){
                   '    <base_call>
                   '}
                   '";
        }
    } else {
        actuals = ["$<i>" | i <- index(formalTypes), f := formalTypes[i]];
        if(hasKeywordParameters(funType)){
            actuals += kwpActuals;
        }
        if(isConstructorType(funType)){
            return "return <makeConstructorCall(funType, actuals, jg)>;";
            //if(isEmpty(funType.kwFields)){
            //    return "$VF.constructor(<funType.adt.adtName>_<funType.label>, new IValue[]{<intercalate(", ", actuals)>})";
            //} else {
            //    return "$VF.constructor(<funType.adt.adtName>_<funType.label>, new IValue[]{<intercalate(", ", actuals[0..-1])>}, <actuals[-1]>)";
            //}
        
        } else {
            externalVars = jg.getExternalVars(of);
            if(!isEmpty(externalVars)){
                actuals +=  [ varName(var, jg) | var <- sort(externalVars), jtype := atype2javatype(var.atype)];
             }
            call_code = "<jg.getAccessorInResolver(of)>(<intercalate(", ", actuals)>)";
            di = jg.getDefine(of).defInfo;
            returns_void = funType.ret == avoid();
            return (di has canFail &&true /*di.canFail*/) ? ( returns_void ? "try { <call_code>; return; } catch (FailReturnFromVoidException e){};\n"
                                                                   : "res = <call_code>;
                                                                     'if(res != null) return <returns_void ? "" : "res">;\n"
                                                    )
                                                  : ( returns_void ? "<call_code>; return;\n"
                                                                   : "return <call_code>;\n"
                                                    );
        }
    }
}

JCode makeConstructorCall(AType funType, list[str] actuals, JGenie jg){
    if(isEmpty(funType.kwFields)){
        return "$VF.constructor(<atype2idpart(funType)>, new IValue[]{<intercalate(", ", actuals)>})";
    } else {
        return "$VF.constructor(<atype2idpart(funType)>, new IValue[]{<intercalate(", ", actuals[0..-1])>}, <actuals[-1]>)";
    }
}

// ---- muModuleVar ----------------------------------------------------------

JCode trans(MuModuleVar var, JGenie jg){
       return "<atype2javatype(var.atype)> <var.name>;";
}



// ---- muFunction ------------------------------------------------------------

bool constantDefaults(lrel[str name, AType atype, MuExp defaultExp] kwpDefaults){
    return all(<str name, AType atype, MuExp defaultExp> <- kwpDefaults, muCon(_) := defaultExp);
}

JCode trans(MuFunction fun, JGenie jg){
    iprintln(fun);
    if(!containedIn(fun.src, jg.getModuleLoc()) )return "";
    ftype = fun.ftype;
    jg.setFunction(fun);
    shortName = getJavaName(jg.getFunctionName());
    visibility = startsWith(shortName, "$CLOSURE") ? "private " : "";
    uncheckedWarning = "";
    if(afunc(AType ret, list[AType] formals, list[Keyword] kwFormals) := ftype){
        returnType = atype2javatype(ftype.ret);
        
        formals = fun.formals;
        tmp = for(i <- index(formals)){
            f = ftype.formals[i];
            println(f);
            append "<atype2javatype(f)> <varName(formals[i], jg)>";
        };
        
        argTypes = intercalate(", ", tmp);
        //argNames = fun.argNames;
        //argTypes = intercalate(", ", ["<atype2javatype(f)> <(f.label? && f.label[0] != "$") ? "<f.label>_<i>" : "$<i>">" | i <- index(ftype.formals), f := ftype.formals[i]]);
        if(!isEmpty(fun.externalVars)){
            ext_actuals = intercalate(", ", ["ValueRef\<<atype2javatype(var.atype)>\> <varName(var, jg)>" | var <- fun.externalVars, var.pos >= 0]);
            argTypes = isEmpty(formals) ? ext_actuals : (isEmpty(ext_actuals) ? argTypes : "<argTypes>, <ext_actuals>");
        }
        kwpActuals = "java.util.Map\<String,IValue\> $kwpActuals";
        kwpDefaults = fun.kwpDefaults;
        constantKwpDefaults = "";
        nonConstantKwpDefaults = "";
        mapCode = "Util.kwpMap(<intercalate(", ", [ *["\"<key>\"", trans(defaultExp,jg)] | <str key, AType tp, MuExp defaultExp> <- kwpDefaults ])>);\n";
        if(!isEmpty(kwFormals)){
            argTypes = isEmpty(argTypes) ? kwpActuals : "<argTypes>, <kwpActuals>";
            if(constantDefaults(kwpDefaults)){
                kwpDefaultsName = "$kwpDefaults_<shortName>";
                jg.setKwpDefaults(kwpDefaultsName);
                constantKwpDefaults = "final java.util.Map\<java.lang.String,IValue\> <kwpDefaultsName> = <mapCode>";
             } else {
                jg.setKwpDefaults("$kwpDefaults");
                nonConstantKwpDefaults =  "java.util.Map\<String,IValue\> $kwpDefaults = <mapCode>";
             }   
        }
        declaredLocalVars = ""; //getLocalVarDeclarations(fun, jg);
        memoCache = fun.isMemo ? "private final MemoizationCache\<IValue\> $memo_<shortName> = new MemoizationCache\<IValue\>();\n" : "";
        return isEmpty(kwFormals) ? "<memoCache><visibility><returnType> <shortName>(<argTypes>){
                                    '    <declaredLocalVars>
                                    '    <trans2Void(fun.body, jg)>
                                    '}"
                                  : "<constantKwpDefaults><memoCache>
                                    '<visibility><returnType> <shortName>(<argTypes>){
                                    '    <nonConstantKwpDefaults>
                                    '    <declaredLocalVars>
                                    '    <trans2Void(fun.body, jg)>
                                    '}";

  
    } else
    if(acons(AType adt, list[AType] fields, list[Keyword] kwFields) := ftype){
        returnType = "IConstructor";
        qname = getJavaName(ftype.label);
        tmp = for(i <- index(fields)){
            f = fields[i];
            append "<atype2javatype(f)> <varName(fields[i], jg)>";
        };
        
        argTypes = intercalate(", ", tmp);
        //argTypes = intercalate(", ", ["<atype2javatype(f)> <f.label? ? "<f.label>_<i>" : "$<i>">" | i <- index(ftype.fields), f := ftype.fields[i]]);
        kwpActuals = "java.util.Map\<String,IValue\> $kwpActuals";
        kwpDefaults = fun.kwpDefaults;
        constantKwpDefaults = "";
        nonConstantKwpDefaults = "";
        mapCode = "Maps.builder()<for(<str key, AType tp, MuExp defaultExp> <- kwpDefaults){>.key(\"<key>\").value(<trans(defaultExp,jg)>)<}>.build();\n";
        if(!isEmpty(kwFields)){
            uncheckedWarning = "@SuppressWarnings(\"unchecked\")";
            argTypes = isEmpty(argTypes) ? kwpActuals : "<argTypes>, <kwpActuals>";
            if(constantDefaults(kwpDefaults)){
                kwpDefaultsName = "<qname>_$kwpDefaults";
                jg.setKwpDefaults(kwpDefaultsName);
                constantKwpDefaults = "final java.util.Map\<java.lang.String,IValue\> <kwpDefaultsName> = <mapCode>";
             } else {
                jg.setKwpDefaults("$kwpDefaults");
                nonConstantKwpDefaults =  "java.util.Map\<String,IValue\> $kwpDefaults = <mapCode>";
             }   
        }
        return "<constantKwpDefaults>
               '<uncheckedWarning>
               '<returnType> <qname>(<argTypes>){
               '     <nonConstantKwpDefaults>
               '     <trans(fun.body, jg)>
               '}";
    } else
        throw "trans MuFunction: <ftype>";
}

JCode call(MuFunction fun, list[str] actuals, JGenie jg){
    return "<fun.qname>(<intercalate(", ", actuals)>)";
}

// ---- muCon -----------------------------------------------------------------                                       

JCode trans(muCon(value v), JGenie jg) = jg.shareConstant(v);

JCode trans(muATypeCon(AType t, map[AType, set[AType]] definitions), JGenie jg) = jg.shareATypeConstant(t, definitions);
                       
JCode trans(muFun1(loc uid), JGenie jg){
   
    fun = muFunctionsByLoc[uid];
    ftype = fun.ftype;
    uid = fun.src;
    //ftype = jg.getType(uid);
    externalVars = jg.getExternalVars(uid);
    currentFun = jg.getFunction();
    externalVarsCurrentFun = jg.getExternalVars(currentFun.src);
    
    nformals = size(ftype.formals);
    sep = nformals > 0 ? "," : "";
    
    funInstance = "new FunctionInstance<nformals>\<<atype2javatype(ftype.ret)><sep><intercalate(",", [atype2javatype(ft) | ft <- ftype.formals])>\>";
    
    actuals = intercalate(", ", ["$<i>" | i <- [0..nformals]]);
    
    ext_actuals = actuals;
    if(!isEmpty(externalVars)){
           ext_actuals = intercalate(", ", [ /*jg.isDefinedInCurrentFunction(var) ? varName(var, jg) :*/ "new ValueRef\<<jtype>\>(<varName(var, jg)>)" | var <- externalVars, jtype := atype2javatype(var.atype)]);
           ext_actuals = isEmpty(actuals) ? ext_actuals : "<actuals>, <ext_actuals>";
    }
    return "<funInstance>((<actuals>) -\> { return <jg.getAccessor(uid)>(<ext_actuals>); })";
}          

          //| muFun2(str fuid, str scopeIn)                       // *muRascal* function constant: nested functions and closures
          //
          //| muOFun(str fuid)                                    // *Rascal* function, i.e., overloaded function at the root
       
JCode trans(muOFun(str fuid), JGenie jg){
    fun = muFunctions[fuid];
    ftype = fun.ftype;
    nformals = fun.nformals;
    sep = nformals > 0 ? "," : "";
    
    funInstance = "new FunctionInstance<nformals>\<<atype2javatype(ftype.ret)><sep><intercalate(",", [atype2javatype(ft) | ft <- ftype.formals])>\>";
    
    formals = intercalate(", ", ["$<i>" | i <- [0..fun.nformals]]);
    ext_formals = formals;
    if(!isEmpty(fun.externalVars)){
           ext_actuals = intercalate(", ", [varName(v, jg) | v <- fun.externalVars]);
           formals = isEmpty(formals) ? ext_actuals : "<actuals>, <ext_actuals>";
    }
    return "<funInstance>((<formals>) -\> { return <colon2ul(fuid)>(<formals>); })";
}

          //| muConstr(str fuid)                                  // Constructor
          
// Variables

//// ---- muModuleVar -----------------------------------------------------------
//
//JCode trans(var:muModuleVar(str name, AType atype), JGenie jg{
//    return name;
//}

// ---- muVar -----------------------------------------------------------------

str varName(muVar(str name, str fuid, int pos, AType atype), JGenie jg)
    = (name[0] != "$") ? "<name><(pos >= 0) ? "_<pos>" : "">" : name;
        
JCode trans(var:muVar(str name, str fuid, int pos, AType atype), JGenie jg)
    = jg.isExternalVar(var) && pos >= 0 ? "<varName(var, jg)>.value" : varName(var, jg);

// ---- muTmpIValue -----------------------------------------------------------------

JCode trans(var: muTmpIValue(str name, str fuid, AType atype), JGenie jg)
    = jg.isExternalVar(var) ? "<name>.value" : name;
    
JCode trans(var: muTmpNative(str name, str fuid, NativeKind nkind), JGenie jg)
    = jg.isExternalVar(var) ? "<name>.value" : name;
  
// ---- muVarDecl --------------------------------------------------------------

JCode trans(muVarDecl(v: muVar(str name, str fuid, int pos, AType atype)), JGenie jg){
    jtype = atype2javatype(atype);
    return jg.isExternalVar(v) ? "ValueRef\<<jtype>\> <varName(v, jg)>;\n"
                               : "<jtype> <varName(v, jg)>;\n";  
}

JCode trans(muVarDecl(v: muTmpIValue(str name, str fuid, AType atype)), JGenie jg){
    jtype = atype2javatype(atype);
    return jg.isExternalVar(v) ? "ValueRef\<<jtype>\> <name>;\n"
                               : "<jtype> <name>;\n";
}

JCode trans(muVarDecl(var: muTmpNative(str name, str fuid, NativeKind nkind)), JGenie jg){
    <base, ref> = native2ref[nkind];
    return jg.isExternalVar(var) ? "<ref> <name>;\n"
                                 : "<base> <name>;\n";
}

  
// ---- muVarInit --------------------------------------------------------------

str parens(str code)
    = endsWith(code, ";\n") ? "(<code[0..-2]>)" : "(<code>)";

JCode trans(muVarInit(v: muVar(str name, str fuid, int pos, AType atype), MuExp exp), JGenie jg){
    jtype = atype2javatype(atype);
    return jg.isExternalVar(v) ? "final ValueRef\<<jtype>\> <varName(v, jg)> = new ValueRef\<<jtype>\>(<trans(exp,jg)>);\n"
                               : "<jtype> <varName(v, jg)> = (<jtype>)<parens(trans(exp, jg))>;\n";  
}

JCode trans(muVarInit(v: muTmpIValue(str name, str fuid, AType atype), MuExp exp), JGenie jg){
    jtype = atype2javatype(atype);
    return jg.isExternalVar(v) ? "final ValueRef\<<jtype>\> <name> = new ValueRef\<<jtype>\>(<trans(exp,jg)>);\n"
                               : "<jtype> <name> = (<jtype>)<parens(trans(exp, jg))>;\n";
}

map[NativeKind, tuple[str,str]] native2ref =
    (nativeInt()            : <"int", "IntRef">,
     nativeBool()           : <"boolean", "BoolRef">,
     nativeListWriter()     : <"IListWriter", "IListWriterRef">,
     nativeSetWriter()      : <"ISetWriter", "ISetWriterRef">,
     nativeMapWriter()      : <"IMapWriter", "IMapWriterRef">,
     nativeMatcher()        : <"Matcher", "MatcherRef">,
     nativeStrWriter()      : <"StringWriter", "StringWriterRef">,
     nativeDescendantIterator()
                            : <"DescendantMatchIterator", "DescendantMatchIteratorRef">,
     nativeTemplate()       : <"Template", "TemplateRef">,
     nativeException()      : <"Exception", "ExceptionRef">,
     nativeGuardedIValue()  : <"GuardedIValue", "GuardedIValueRef">
     );

JCode trans(muVarInit(var: muTmpNative(str name, str fuid, NativeKind nkind), MuExp exp), JGenie jg){
    rhs = muCon(value v) := exp ? "<v>" : trans(exp, jg);   // TODO does not work for all constants, e.g. datetime
    <base, ref> = native2ref[nkind];
    return jg.isExternalVar(var) ? "final <ref> <name> = new <ref>(<rhs>);\n"
                                 : "<base> <name> = <rhs>;\n";
}

// --- muConInit --------------------------------------------------------------

 JCode trans(muConInit(v:muVar(str name, str fuid, int pos, AType atype), MuExp exp), JGenie jg){
    jtype = atype2javatype(atype);
    if(jg.isExternalVar(v)){  
        return "final ValueRef\<<jtype>\> <varName(v, jg)> = new ValueRef\<<jtype>\>(<trans(exp,jg)>);\n";
    }
    return "<jtype> <varName(v, jg)> = <transWithCast(atype, exp, jg)>;\n";
}
    
JCode trans(muConInit(v:muTmpIValue(str name, str fuid, AType atype), MuExp exp), JGenie jg){
    jtype = atype2javatype(atype);
    return jg.isExternalVar(v) ? "final ValueRef\<<jtype>\> <varName(v,jg)> = new ValueRef\<<jtype>\>(<trans(exp,jg)>);\n"
                               : "final <jtype> <name> = <transWithCast(atype, exp, jg)>;\n";
}

JCode trans(muConInit(var:muTmpNative(str name, str fuid, NativeKind nkind), MuExp exp), JGenie jg){
    rhs = muCon(value v) := exp ? "<v>" : trans(exp, jg);
    <base, ref> = native2ref[nkind];
    return jg.isExternalVar(var) ? "final <ref> <varName(var, jg)> = new <ref>(<rhs>);\n"
                                 : "final <base> <name> = <rhs>;\n";
}

str transWithCast(AType atype, con:muCon(c), JGenie jg) = trans(con, jg);

default str transWithCast(AType atype, MuExp exp, JGenie jg) 
    = atype == avoid() ? trans(exp, jg) : "((<atype2javatype(atype)>)<parens(trans(exp, jg))>)";

// ---- muAssign --------------------------------------------------------------

JCode trans(muAssign(v:muVar(str name, str fuid, int pos, AType atype), MuExp exp), JGenie jg)
    = "<varName(v, jg)><jg.isExternalVar(v) ? ".value" : ""> = <transWithCast(atype, exp, jg)>;\n";
    
JCode trans(muAssign(v:muTmpIValue(str name, str fuid, AType atype), MuExp exp), JGenie jg)
    = "<name><jg.isExternalVar(v) ? ".value" : ""> = <trans(exp, jg)>;\n";

JCode trans(muAssign(v:muTmpNative(str name, str fuid, NativeKind nkind), MuExp exp), JGenie jg){
    return"<name><jg.isExternalVar(v) ? ".value" : ""> = <trans2Native(exp, nkind, jg)>;\n";
}

// muGetAnno
JCode trans(muGetAnno(MuExp exp, AType resultType, str annoName), JGenie jg)
    = "((<atype2javatype(resultType)>)annotation_get(<trans(exp, jg)>,\"<annoName>\"))";

// muGuardedGetAnno
JCode trans(muGuardedGetAnno(MuExp exp, AType resultType, str annoName), JGenie jg)
    = "guarded_annotation_get(<trans(exp, jg)>,\"<annoName>\")";
    
// muSetAnno
JCode trans(muSetAnno(MuExp exp, AType resultType, str annoName, MuExp repl), JGenie jg)
    = "((<atype2javatype(resultType)>)<trans(exp, jg)>.asAnnotatable().setAnnotation(\"<annoName>\",<trans(repl, jg)>))";

// Call/Apply/return      

JCode trans(muCall(MuExp fun, AType ftype, list[MuExp] largs), JGenie jg){
    actuals = [trans(arg, jg) | arg <- largs];
         
    if(muConstr(AType ctype) := fun){
        return makeConstructorCall(ctype, actuals, jg);        
    }
    if(muConstrCompanion(str fname) := fun){
        return call(muFunctions[fname], actuals, jg);
    }
    if(muCon(str s) := fun){
        if(map[str,value] kwmap := actuals[-1]){
            return makeNode(s, actuals[0..-1], keywordParameters = kwmap);
        }
        throw "muCall: kwmap, <actuals>";
    }
    if(muVar(str name, str fuid, int pos, AType atype):= fun){
        return "<trans(fun, jg)>(<intercalate(", ", actuals)>)";
    }
    if(muFun1(loc uid) := fun){
       if(containedIn(uid, jg.getModuleLoc())){
         muFun = muFunctionsByLoc[uid];
         if(ftype.varArgs){
            n = size(ftype.formals);
            vargs = largs[n -1 .. ];
            actuals = actuals[ .. n];
            actuals += "$VF.list(<intercalate(",", vargs)>)";
         }
         externalVars = jg.getExternalVars(uid);
         if(!isEmpty(externalVars)){
            actuals += [ varName(var, jg)| var <- externalVars, var.pos >= 0 ];
         }
         idx = findFirst(muFun.qname, "$");
         shortName = muFun.qname[idx+1 .. ];
         return "<shortName>(<intercalate(", ", actuals)>)";
       } else {    
         if(!isEmpty(ftype.kwFormals)){
           if(map[str,value] kwmap := actuals[-1]){
              actuals = actuals[..-1] + [ trans(val, jg) | kw <- kwmap ];
              return makeNode(s, actuals[0..-1], keywordParameters = kwmap);
           } else {
              throw "muCall: <fun>, no keyword parameters found";
           }
         }
         //actuals += "Collections.emptyMap()";
         externalVars = jg.getExternalVars(uid);
         if(!isEmpty(externalVars)){
            actuals += [ varName(var, jg)| var <- externalVars, var.pos >= 0 ];
         }
         call_code = "<jg.getAccessor(uid)>(<intercalate(", ", actuals)>)";
         return ftype.ret == avoid() ? call_code : "((<atype2javatype(ftype.ret)>)<call_code>)";
       }
    }
    
    throw "muCall: <fun>";
}

// ---- muOCall3 --------------------------------------------------------------

list[str] getActuals(list[MuExp] largs, JGenie jg)
    = [ trans(largs[i], jg) | i <- index(largs) ];
    //= [ "(<atype2javatype(atypes[i])>)(<trans(largs[i], jg)>)" | i <- index(largs) ];

JCode trans(muOCall3(MuExp fun, AType ftype, list[MuExp] largs, loc src), JGenie jg){
println("muOCall3((<fun>, <ftype>, ..., <src>");
    if(muOFun(str fname) := fun){;
        //if(overloadedAType(overloads) := ftype){
            return "$me.<resolved2overloaded[fname]>_<atype2idpart(ftype)>(<intercalate(", ", getActuals(largs, jg))>)";
       // } else {
       //         return "<replaceAll(fname, "::", "_")>(<intercalate(", ", actuals)>)";
      //  }
    }
    
    if(muFun1(loc uid) := fun){
        return "<jg.getAccessor(uid)>(<intercalate(", ", getActuals(largs, jg))>)";
    }
    if(muCon(str s) := fun){
        return "$VF.node(<intercalate(", ", getActuals(largs, jg))>)";
        //} else {
        //    return "$VF.node((<intercalate(", ", actuals[0..-1])>, keywordParameters=<actuals[-1]>)";
        //}
        throw "mOCall3: kwmap, <actuals>";
    }
    cst = open = close = "";
    if(ftype.ret != avoid()){
            open = "("; close = ")";
            cst = "(<atype2javatype(ftype)>)";
    }
    return "<open><cst><trans(fun, jg)><close>.call(<intercalate(", ", getActuals(largs, jg))>)";
}

// ---- muKwpGetField ------------------------------------------------------
JCode trans(muKwpGetField(AType resultType,  AType consType, MuExp cons, str fieldName), JGenie jg)
    = "$get_<consType.adt.adtName>_<fieldName>(<trans(cons, jg)>)"; // TODO exception?

// ---- muGetField ---------------------------------------------------------

JCode trans(muGetField(AType resultType, aloc(), MuExp exp, str fieldName), JGenie jg)
    = "((<atype2javatype(resultType)>) aloc_get_field(<trans(exp,jg)>, \"<fieldName>\"))";

JCode trans(muGetField(AType resultType, adatetime(), MuExp exp, str fieldName), JGenie jg)
    = "((<atype2javatype(resultType)>) adatetime_get_field(<trans(exp,jg)>, \"<fieldName>\"))";
   // = "((<atype2javatype(resultType)>) adatetime_get_field(<transWithCast(adatetime(), exp,jg)>, \"<fieldName>\"))";

JCode trans(muGetField(AType resultType, anode(_), MuExp exp, str fieldName), JGenie jg)
    = "((<atype2javatype(resultType)>) anode_get_field(<trans(exp,jg)>, \"<fieldName>\"))";
        
JCode trans(muGetField(AType resultType, areified(AType atype), MuExp exp, str fieldName), JGenie jg)
    = "((<atype2javatype(resultType)>) areified_get_field(<trans(exp,jg)>, \"<fieldName>\"))";

default JCode trans(muGetField(AType resultType, AType consType, MuExp cons, str fieldName), JGenie jg){
    base = trans(cons, jg);
    qFieldName = "\"<fieldName>\"";
    println("muGetField: <resultType>, <consType>, <fieldName>");
    for(field <- consType.fields){
        if(fieldName == field.label){
            return "((<atype2javatype(resultType)>)<base>.get(<qFieldName>))";
            //return "((<atype2javatype(field)>)<base>.get(<qFieldName>))";
        }
    }
   
    for(<AType kwType, Expression exp> <- consType.kwFields){
        if(fieldName == kwType.label){
            expCode = trans(exp, jg);
            if(muCon(_) := expCode){
                "<base>.asWithKeywordParameters().hasParameter(<qFieldName>) ? ((<atype2javatype(resultType)>)<base>.asWithKeywordParameters().getParameter(<qFieldName>)) : <expCode>";
            } else {
                return "((<atype2javatype(resultType)>)<base>.asWithKeywordParameters().getParameter(<qFieldName>))";
            }
        }
    }
    throw "muGetField <resultType>, <consType>, <fieldName>";
 }
 
 // ---- muGuardedGetField -------------------------------------------------
 
 JCode trans(muGuardedGetField(AType resultType, aloc(), MuExp exp, str fieldName), JGenie jg)
    = "guarded_aloc_get_field(<trans(exp,jg)>, \"<fieldName>\")";

JCode trans(muGuardedGetField(AType resultType, adatetime(), MuExp exp, str fieldName), JGenie jg)
    = "guarded_adatetime_get_field(<trans(exp,jg)>, \"fieldName\")";

default JCode trans(muGuardedGetField(AType resultType, AType consType, MuExp cons, str fieldName), JGenie jg){
    base = trans(cons, jg);
    qFieldName = "\"<fieldName>\"";
    for(field <- consType.fields){
        if(fieldName == field.label){
            return "((<atype2javatype(field)>)<base>.get(<qFieldName>))";
        }
    }
   
    for(<AType kwType, Expression exp> <- consType.kwFields){
        if(fieldName == kwType.label){
            expCode = trans(exp, jg);
            if(muCon(_) := expCode){
                "<base>.asWithKeywordParameters().hasParameter(<qFieldName>) ? <base>.asWithKeywordParameters().getParameter(<qFieldName>) : <expCode>";
            } else {
                return "<base>.asWithKeywordParameters().getParameter(<qFieldName>)";
            }
        }
    }
     throw "muGuardedGetField <resultType>, <consType>, <fieldName>";
 }

// ---- muSetField ------------------------------------------------------------

JCode trans(muSetField(AType resultType, aloc(), MuExp baseExp, str fieldName, MuExp repl), JGenie jg)
    = "aloc_field_update(<trans(baseExp, jg)>, \"<fieldName>\", <trans(repl, jg)>)";

JCode trans(muSetField(AType resultType, adatetime(), MuExp baseExp, str fieldName, MuExp repl), JGenie jg)
    = "adatetime_field_update(<trans(baseExp, jg)>, \"<fieldName>\", <trans(repl, jg)>)";

    
default JCode trans(muSetField(AType resultType, AType baseType, MuExp baseExp, str fieldName, MuExp repl), JGenie jg)
    = "<trans(baseExp, jg)>.set(\"<fieldName>\", <trans(repl, jg)>)";
    
JCode trans(muSetField(AType resultType, AType baseType, MuExp baseExp, int fieldIndex, MuExp repl), JGenie jg)
    = "atuple_update(<trans(baseExp, jg)>, <fieldIndex>,  <trans(repl, jg)>)" when isTupleType(resultType);
    
//// ---- muCallPrim2 -----------------------------------------------------------
//
//JCode trans(muCallPrim2(str name, loc src), JGenie jg){
//    return transPrim(name, [], jg);
//}

// ---- muCallPrim3 -----------------------------------------------------------

JCode trans(muCallPrim3(str name, AType result, list[AType] details, list[MuExp] exps, loc src), JGenie jg){
    actuals = transPrimArgs(name, result, details, exps, jg);
    return transPrim(name, result, details, actuals, jg);
}

JCode trans(muCallJava(str name, str class, AType funType, int reflect, list[MuExp] largs, str enclosingFun), JGenie jg){
    jg.addImportedLibrary(class);
  
    actuals = [ trans(arg, jg) | arg <- largs ];
    if(!isEmpty(funType.kwFormals)){
        kwpDefaultsVar = jg.getKwpDefaults();
        kwpActuals = "$kwpActuals"; 
        for(kwFormal <- funType.kwFormals){
            kwName = kwFormal.fieldType.label;
            actuals += "(<atype2javatype(kwFormal.fieldType)>)(<kwpActuals>.containsKey(\"<kwName>\") ? <kwpActuals>.get(\"<kwName>\") : <kwpDefaultsVar>.get(\"<kwName>\"))";
        }
    }
    if(reflect == 1){
        actuals += "rex";
    }
    cst = funType.ret == avoid() ? "" : "(<atype2javatype(funType.ret)>)";
    semicolon = "";
    return "<getClassName(class)>.<name>(<intercalate(", ", actuals)>)<semicolon>";
}


// ---- muReturn0 -------------------------------------------------------------

JCode trans(muReturn0(), JGenie jg){
    return "return;";
}

JCode trans(muReturn0FromVisit(), JGenie jg)
    = "ts.setLeavingVisit(true);
      'return;\n";

str semi(str code)
    = /[;}][ \n]*/ := code ? code : "<code>;";
   // = (endsWith(code, ";") || endsWith(code, ";\n") || endsWith(code, "}") || endsWith(code, "}\n")) ? code : "<code>;";

str semi_nl(str code)
    = (endsWith(code, ";") || endsWith(code, ";\n") || endsWith(code, "}") || endsWith(code, "}\n")) ? code : "<code>;\n";
 
JCode trans2Void(MuExp exp, JGenie jg)
   = ""
   when getName(exp) in {"muCon", "muVar", "muTmp"};

JCode trans2Void(MuExp exp, JGenie jg)
   =  semi_nl(trans(exp, jg))
   when getName(exp) in {"muOCall3", "muCall", "muReturn0", "muReturn1"};
   
JCode trans2Void(muBlock(list[MuExp] exps), JGenie jg)
    = "<for(exp <- exps){><trans2Void(exp, jg)><}>";

JCode trans2Void(muIfExp(MuExp cond, muBlock([]), MuExp elsePart), JGenie jg)
   = "if(!<trans2NativeBool(cond, jg)>){
     '  <trans2Void(elsePart, jg)>
     '}\n";
 
 JCode trans2Void(muIfExp(MuExp cond, MuExp thenPart, muBlock([])), JGenie jg)
   = "if(<trans2NativeBool(cond, jg)>){
     '  <trans2Void(thenPart, jg)>
     '}\n";

default JCode trans2Void(muIfExp(MuExp cond, MuExp thenPart, MuExp elsePart), JGenie jg)
   = "if(<trans2NativeBool(cond, jg)>){
     '  <trans2Void(thenPart, jg)>
     '} else {
     '  <trans2Void(elsePart, jg)>
     '}\n";
 
default JCode trans2Void(MuExp exp, JGenie jg){
    return semi(trans(exp, jg));
}   
// ---- muReturn1 -------------------------------------------------------------

JCode trans2IValue(MuExp exp, JGenie jg){
    if(producesNativeBool(exp))
        return trans2IBool(exp, jg);
    if(producesNativeInt(exp))
        return trans2IInteger(exp, jg);
    return trans(exp, jg);
}

JCode trans(muReturn1(AType t, muBlock([])), JGenie jg){
    return ""; // "return;\n";
}

default JCode trans(muReturn1(AType result, MuExp exp), JGenie jg){
    return "return <castArg(result, trans2IValue(exp, jg))>;\n";
    //return "return (<atype2javatype(result)>)(<trans2IValue(exp, jg)>);\n";
}

JCode trans(muReturn1FromVisit(AType result, MuExp exp), JGenie jg)
    = "ts.setLeavingVisit(true);
      'return (<atype2javatype(result)>)(<trans(exp, jg)>);\n";

//          | muFilterReturn()                                    // Return for filer statement

// ---- muKwpActuals ----------------------------------------------------------

JCode trans(muKwpActuals(lrel[str name, MuExp exp] kwpActuals), JGenie jg){
    if(isEmpty(kwpActuals)) return "Collections.emptyMap()";
    return "Util.kwpMap(<intercalate(", ",  [ *["\"<key>\"", trans(exp, jg)] | <str key,  MuExp exp> <- kwpActuals])>)";
}

// ---- muKwpMap --------------------------------------------------------------

JCode trans(muKwpMap(lrel[str kwName, AType atype, MuExp defaultExp] kwpDefaults), JGenie jg){
    kwpDefaultsVar = jg.getKwpDefaults();
    kwpActuals = "$kwpActuals"; 
    return "
           '    <kwpActuals>.isEmpty() ? <kwpDefaultsVar>
           '                           : Util.kwpMap(<for(<str key,  AType atype, MuExp exp> <- kwpDefaults, muCon(_) !:= exp){>\"<key>\", <kwpActuals>.containsKey(\"<key>\") ? <kwpActuals>.get(\"<key>\") : <trans(exp,jg)>)<}>)";
}

// ---- muVarKwp --------------------------------------------------------------

JCode trans(var:muVarKwp(str name, str fuid, AType atype),  JGenie jg)
    = "(<atype2javatype(atype)>) ($kwpActuals.containsKey(\"<name>\") ? $kwpActuals.get(\"<name>\") : <jg.getKwpDefaults()>.get(\"<name>\"))";

JCode trans(muAssign(muVarKwp(str name, str fuid, AType atype), MuExp exp), JGenie jg)
    = "$kwpActuals.put(\"<name>\", <trans(exp, jg)>);\n";

JCode trans(muIsKwpDefined(MuExp exp, str kwpName), JGenie jg)
    = "<trans(exp, jg)>.asWithKeywordParameters().hasParameter(\"<kwpName>\")";

JCode trans(muHasKwp(MuExp exp, str kwName), JGenie jg)
    = "<trans(exp, jg)>.asWithKeywordParameters().hasParameter(\"<kwName>\")";

JCode trans(muGetKwp(MuExp exp, AType atype, str kwpName), JGenie jg){
   if(acons(AType adt, list[AType] fields, list[Keyword] kwFields) := atype){
        return "$get_<atype.adtName>_<kwpName>(<trans(exp, jg)>)";
   } else if(anode(_) := atype){
       return "<trans(exp, jg)>.asWithKeywordParameters().getParameter(\"<kwpName>\")";
   } else if(aadt(str adtName, list[AType] parameters, SyntaxRole syntaxRole) := atype){
       return "$get_<adtName>_<kwpName>(<trans(exp, jg)>)";
   }
   throw "muGetKwp: <atype>, <kwpName>";
}

JCode trans(muGetKwpFromConstructor(MuExp exp, AType atype, str kwpName), JGenie jg)
    = "(<atype2javatype(atype)>)<trans(exp, jg)>.asWithKeywordParameters().getParameter(\"<kwpName>\")";
 

JCode trans(muInsert(MuExp exp, AType atype), JGenie jg)
    = "ts.setMatchedAndChanged(true, true);
      'return <trans(exp, jg)>;\n";

// Assignment, If and While

JCode trans(muIfelse(MuExp cond, MuExp thenPart, MuExp elsePart), JGenie jg){
    return "if(<trans2NativeBool(cond, jg)>){
            '   <trans2Void(thenPart, jg)>
            '} else {
            '   <trans2Void(elsePart, jg)>
            '}\n";
}

JCode trans(muIfExp(MuExp cond, muBlock([]), MuExp elsePart), JGenie jg)
   = "if(!<trans2NativeBool(cond, jg)>){
     '  <trans2Void(elsePart, jg)>
     '}\n";
   
JCode trans(muIfExp(MuExp cond, MuExp thenPart, muBlock([])), JGenie jg)
   = "if(<trans2NativeBool(cond, jg)>){
     '  <trans2Void(thenPart, jg)>
     '}\n";

default JCode trans(muIfExp(MuExp cond, MuExp thenPart, MuExp elsePart), JGenie jg)
   = "(<trans2NativeBool(cond, jg)> ? <trans(thenPart, jg)> : <trans(elsePart, jg)>)";
 
JCode trans(muIf(MuExp cond, MuExp thenPart), JGenie jg){
    return "if(<trans2NativeBool(cond, jg)>){
            '   <trans2Void(thenPart, jg)>
            '}\n";
}

JCode trans(muIfEqualOrAssign(MuExp var, MuExp other, MuExp body), JGenie jg){
    return "if(<trans(var, jg)> == null){
           '    <trans(muAssign(var, other), jg)>
           '    <trans(body, jg)>
           '} else {
           '    <trans(muAssign(var, other), jg)>
           '    if(<trans(var, jg)>.isEqual(<trans(other, jg)>)){
           '       <trans(body, jg)>
           '    }
           '}\n";
}

JCode trans(muWhileDo(str label, MuExp cond, MuExp body), JGenie jg){
    return "<isEmpty(label) ? "" : "<label>:">
           '    while(<trans2NativeBool(cond, jg)>){
           '        <trans2Void(body, jg)>
           '    }\n";
}

JCode trans(muDoWhile(str label, MuExp body, MuExp cond), JGenie jg){
    return "<isEmpty(label) ? "" : "<label>:">
           '    do{
           '        <trans2Void(body, jg)>
           '    } while(<trans2NativeBool(cond, jg)>);\n";
}

JCode trans(mw: muForAll(str btscope, MuExp var, AType iterType, MuExp iterable, MuExp body), JGenie jg){

    noInnerLoops = false; ///muForAll(_,_,_,_,_) := body;
    iterCode = muCallPrim3("subsets", _, _, _, _) := iterable ? trans(iterable, jg) : transWithCast(iterType, iterable, jg);
//  'for(<atype2javatype(getEnumeratorElementType(iterType))> <var.name> : <iterCode>){   
    return
    "<isEmpty(btscope) ? "" : "<btscope>:">
    'for(IValue <var.name> : <iterCode>){
    '    <trans2Void(body, jg)>
    '}
    '<noInnerLoops ? "throw new RuntimeException(\"muForAll exhausted\");" : "">\n";
}

JCode trans(muEnter(btscope, muBlock([*exps, muSucceed(btscope)])), JGenie jg)
    = "<trans(muBlock(exps), jg)>";
    
JCode trans(muEnter(btscope, muFail(btscope)), JGenie jg)
    = "";
    
JCode trans(muEnter(btscope, asg:muAssign(_,_)), JGenie jg)
    = trans(asg, jg);
    
JCode trans(muEnter(btscope,ret: muReturn1(_,_)), JGenie jg)
    = trans(ret, jg);

default JCode trans(muEnter(btscope, MuExp exp), JGenie jg)
    = "<btscope>: 
      '    do {
      '        <trans(exp, jg)>
      '    } while(false);\n";

JCode trans(muSucceed(str label), JGenie jg)
    = "break <label>;";

JCode trans(muFail(str label), JGenie jg)
    = "continue <label>;";
    
JCode trans(muBreak(str label), JGenie jg)
    = "break <label>;\n";
    
JCode trans(muContinue(str label), JGenie jg)
    = "continue <label>;\n";

JCode trans(muForRange(str label, MuExp var, MuExp first, MuExp second, MuExp last, MuExp exp), JGenie jg){
    //TODO: cover all combinations int/real
    base = getName(var.atype);
    fst = jg.newTmp("fst"); fstContrib = "";
    scd = jg.newTmp("scd"); scdContrib = "";
    lst = jg.newTmp("lst"); lstContrib = "";
    dir = jg.newTmp("dir"); dirContrib = ""; dirKnown = false; dirUp = true;
    delta = jg.newTmp("delta"); deltaContrib = "";
    deltaVal = delta;
    
    if(muCon(_) := first) fst = trans(first, jg); else fstContrib = "final <atype2javatype(var.atype)> <fst> = <trans(first, jg)>;\n";
    if(muCon(_) := last) lst = trans(last, jg); else lstContrib = "final <atype2javatype(var.atype)> <lst> = <trans(last, jg)>;\n";
    
    testCode = "";
    if(muCon(int f) := first && muCon(int l) := last){
        dirKnown = true;
        dirUp = f < l;
        dirContrib = "final boolean <dir> = <f < l>;\n";
        testCode = dirUp ? "<transPrim("less", abool(), [var.atype, var.atype], [trans(var,jg), lst], jg)>.getValue()"
                         : "<transPrim("greater", abool(), [var.atype, var.atype], [trans(var,jg), lst], jg)>.getValue()";
    } else {
        dirContrib = "final boolean <dir> = <fst>.less(<lst>).getValue();\n";
        testCode = "<dir> ? <transPrim("less", abool(), [var.atype, var.atype], [trans(var,jg), lst], jg)>.getValue() 
                          : <transPrim("greater",abool(), [var.atype, var.atype], [trans(var,jg), lst], jg)>.getValue()";
    }
    
    if(muCon(int f) := first && muCon(int s) := second){
        if(s == 0){
            if(dirKnown){
               dirContrib = "";
               deltaVal = dirUp ? trans(muCon(1), jg) : trans(muCon(-1), jg);
            } else {
               deltaVal = "<dir> ? <trans(muCon(1), jg)> : <trans(muCon(-1), jg)>";
            }
        } else {
            deltaContrib = "final <atype2javatype(var.atype)> <delta> = <trans(second, jg)>.subtract(<fst>);\n";
        }
    
    } else {
        deltaCode = muCon(0) := second ? "<dir> ? <trans(muCon(1), jg)> : <trans(muCon(-1), jg)>" : "<trans(second, jg)>.subtract(<fst>)";
        deltaContrib = "final <atype2javatype(var.atype)> <delta> = <deltaCode>;\n";
    }
    
    return 
    "<fstContrib><lstContrib><dirContrib><deltaContrib>
    '<isEmpty(label) ? "" : "<label>:">
    'for(<atype2javatype(var.atype)> <var.name> = <fst>; <testCode>; <var.name> = <transPrim("add", var.atype, [var.atype, var.atype], [trans(var,jg), deltaVal], jg)>){
    '    <trans2Void(exp, jg)>
    '}
    '";
}

JCode trans(muForRangeInt(str label, MuExp var, int ifirst, int istep, MuExp last, MuExp exp), JGenie jg){
    return 
    "<isEmpty(label) ? "" : "<label>:">
    'for(int <var.name> = <ifirst>; <var.name> \< <trans(last, jg)>; <var.name> += <istep>){
    '   <trans(exp, jg)>
    '}
    '";
}
         
JCode trans(muSwitch(MuExp exp, list[MuCase] cases, MuExp defaultExp, bool useConcreteFingerprint), JGenie jg){
    return "<trans(exp, jg)>
           'switch(Util.getFingerprint(<exp.var.name>, <useConcreteFingerprint>)){
           '<for(muCase(int fingerprint, MuExp exp) <- cases){>
           '    case <fingerprint>:
           '        <trans(exp, jg)>
           '<}>
           '    <defaultExp == muBlock([]) ? "" : "default: <trans(defaultExp, jg)>">
           '}\n";
}

JCode trans(muVisit(MuExp exp, list[MuCase] cases, MuExp defaultExp, VisitDescriptor vdescriptor), JGenie jg){
    direction  = vdescriptor.direction  ? "BottomUp"   : "TopDown";
    progress   = vdescriptor.progress   ? "Continuing" : "Breaking";
    fixedpoint = vdescriptor.fixedpoint ? "Yes"        : "No";
    rebuild    = vdescriptor.rebuild    ? "Yes"        : "No";
    
    defaultCode = defaultExp == muBlock([]) ? "" : 
                  "    default: 
                  '        <trans(defaultExp, jg)>";
    return
      "$TRAVERSE.traverse(DIRECTION.<direction>, PROGRESS.<progress>, FIXEDPOINT.<fixedpoint>, REBUILD.<rebuild>, 
      '     new DescendantDescriptor($VF.set(), $VF.set(), null, $VF.bool(false), null),
      '     <trans(exp.exp,jg)>,
      '     (IVisitFunction) (IValue <exp.var.name>, TraversalState ts) -\> {
      '         switch(Util.getFingerprint(<exp.var.name>, <vdescriptor.descendant.useConcreteFingerprint>)){
      '         <for(muCase(int fingerprint, MuExp exp) <- cases){>
      '             case <fingerprint>:
      '                 <trans(exp, jg)>
      '         <}>
      '         <defaultCode>
      '         }
      '         return <exp.var.name>;
      '     })";
}  

JCode trans(muDescendantMatchIterator(MuExp subject, DescendantDescriptor ddescriptor), JGenie jg)
    = "new DescendantMatchIterator(<trans(subject, jg)>, new DescendantDescriptor($VF.set(), $VF.set(), null, $VF.bool(false), null))";


JCode trans(muFailCase(), JGenie jg)
    = "break;\n";
    
JCode trans(muSucceedSwitchCase(), JGenie jg)
    = "break;";
    
JCode trans(muSucceedVisitCase(), JGenie jg)
    = "ts.setMatched(true); break;";

// ---- muFailReturn ----------------------------------------------------------

JCode trans(muFailReturn(AType funType),  JGenie jg)
    = funType.ret == avoid() ? "throw new FailReturnFromVoidException();"
                             : "return null;";
    
// ---- muCheckMemo -----------------------------------------------------------

JCode trans(muCheckMemo(AType funType, list[MuExp] args/*, map[str,value] kwargs*/, MuExp body), JGenie jg){
    cache = "$memo_<jg.getFunctionName()>";
    kwpActuals = isEmpty(funType.kwFormals) ? "Collections.emptyMap()" : "$kwpActuals";
    return "final IValue[] $actuals = new IValue[] {<intercalate(",", [trans(arg, jg) | arg <- args])>};
           'IValue $memoVal = <cache>.getStoredResult($actuals, <kwpActuals>);
           'if($memoVal != null) return (<atype2javatype(funType.ret)>) $memoVal;
           '<trans(body, jg)>";
}

// ---- muMemoReturn ----------------------------------------------------------

JCode trans(muMemoReturn(AType funType, list[MuExp] args, MuExp functionResult), JGenie jg){
    cache = "$memo_<jg.getFunctionName()>";
    kwpActuals = isEmpty(funType.kwFormals) ? "Collections.emptyMap()" : "$kwpActuals";
    return "$memoVal = <trans(functionResult, jg)>;
           '<cache>.storeResult($actuals, <kwpActuals>, $memoVal);
           'return (<atype2javatype(funType.ret)>)$memoVal;";
}
           
 
// Lists of expressions

JCode trans(muBlock(list[MuExp] exps), JGenie jg){
    return "<for(exp <- exps){><trans2Void(exp, jg)><}>";
}
   
JCode trans(muValueBlock(AType t, list[MuExp] exps), JGenie jg){
    return "<for(exp <- exps[0..-1]){><trans2Void(exp, jg)><}> 
           '<trans(exps[-1], jg)>";

    //return "((Block) () -\> {
    //       '<for(exp <- exps[0..-1]){><trans2Void(exp, jg)><}> 
    //       '<trans(muReturn1(t, exps[-1]), jg)>
    //       '}).compute()";
}

// Exceptions
       
JCode trans(muThrow(muTmpNative(str name, str fuid, nativeException()), loc src), JGenie jg){
    return "throw <name>;";
}

default JCode trans(muThrow(MuExp exp, loc src), JGenie jg){
    return "throw new RascalException(<trans(exp, jg)>);";
}

JCode trans(muTry(MuExp exp, MuCatch \catch, MuExp \finally), JGenie jg){
println(exp);
println(\catch);
println(\finally);
finallyCode = trans(\finally, jg);
println(finallyCode);
    return "try {
                <trans(exp, jg)>
           '} <trans(\catch, jg)>
           '<if(!isEmpty(finallyCode)){>finally { 
           '    <finallyCode>} <}>
           ";
}  

JCode trans(muCatch(MuExp thrown_as_exception, MuExp thrown, MuExp body), JGenie jg){
    jtype = atype2javatype(thrown.atype);
    return "catch (RascalException <thrown_as_exception.name>) {
           '    IValue <thrown.name> = <thrown_as_exception.name>.getValue();
           '   
           '    <trans(body, jg)>
           '}";
}

// ---- muCheckArgTypeAndCopy -------------------------------------------------

JCode trans(muCheckArgTypeAndCopy(str name, int from, AType tp, int to), JGenie jg)
    = "";
    //= "<atype2javatype(tp)> <name>;
    //  'if(<name>$<from>.getType().isSubtypeOf(<atype2typestore(tp)>)).getValue()){
    //  '   <name> = <name>$<from>;
    //  '} else {
    //  '   return null;
    //  '}";

str getIntegerFor(MuExp exp)
    = producesNativeInt(exp) ? "" : ".getValue()";
    
// ---- trans2Native ---------------------------------------------------------
 
 JCode trans2Native(MuExp exp, nativeInt(), JGenie jg)
    = trans2NativeInt(exp, jg);
    
JCode trans2Native(MuExp exp, nativeBool(), JGenie jg)
    = trans2NativeBool(exp, jg);  
    
JCode trans2Native(MuExp exp, NativeKind nkind, JGenie jg) 
    = trans(exp, jg);
    
JCode trans2NativeBool(muCon(bool b), JGenie jg)
    = "<b>";
 
default JCode trans2NativeBool(MuExp exp, JGenie jg)
    = producesNativeBool(exp) ? trans(exp, jg) : "((IBool)(<trans(exp, jg)>)).getValue()";
  
JCode trans2NativeInt(muCon(int n), JGenie jg)
    = "<n>";
    
default JCode trans2NativeInt(MuExp exp, JGenie jg)
    = "<trans(exp, jg)><producesNativeInt(exp) ? "" : ".intValue()">";
    
JCode trans2IInteger(MuExp exp, JGenie jg)
    = producesNativeInt(exp) ? "$VF.integer(<trans(exp, jg)>)" : trans(exp, jg);
    
JCode trans2IBool(MuExp exp, JGenie jg)
    = producesNativeBool(exp) ? "$VF.bool(<trans(exp, jg)>)" : trans(exp, jg);

JCode trans2NativeStr(muCon(str s), JGenie jg)
    = "\"<escapeForJ(s)>\"";
    
default JCode trans2NativeStr(MuExp exp, JGenie jg)
    = "<transWithCast(astr(), exp, jg)>.getValue()";

// -----

JCode trans(muRequire(MuExp exp, str msg, loc src), JGenie jg)
    = "if(!(<trans2NativeBool(exp, jg)>)){
      ' throw new RuntimeException(\"<msg> at <src>\");
      '}\n";
 
JCode trans(muEqual(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans(exp1, jg)>.isEqual(<trans(exp2, jg)>)";
      
JCode trans(muEqualNativeInt(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans2NativeInt(exp1, jg)> == <trans2NativeInt(exp2, jg)>";
    
JCode trans(muNotNegativeNativeInt(MuExp exp), JGenie jg)
    = "<trans2NativeInt(exp, jg)> \>= 0";

JCode trans(muValueIsSubType(MuExp exp, AType tp), JGenie jg){
    return !isVarOrTmp(exp) && exp has atype && exp.atype == tp ? "true"
                      : "<trans(exp, jg)>.getType().isSubtypeOf(<jg.shareType(tp)>)";
}
JCode trans(muValueIsSubTypeOfValue(MuExp exp1, MuExp exp2), JGenie jg)
    ="<trans(exp1, jg)>.getType().isSubtypeOf(<trans(exp2, jg)>.getType())";
    

JCode trans(muHasTypeAndArity(AType atype, int arity, MuExp exp), JGenie jg){
    v = trans(exp, jg);
    t = atype2javatype(atype);
    switch(getName(atype)){
        case "atuple": return "<v> instanceof <t> && ((<t>)<v>).arity() == <arity>";
    }
    throw "muHasTypeAndArity: <atype>, <arity>";
}

JCode trans(muHasNameAndArity(AType atype, str name, int arity, MuExp exp), JGenie jg){
    v = trans(exp, jg);
    if(aadt(str adtName, list[AType] parameters, SyntaxRole syntaxRole) := atype){
       //return "<v>.getConstructorType() == <adtName>_<name>_<arity>";
       return "<v>.arity() == <arity> && <v>.getType() == <getADTName(adtName)>";
    } else {
        return "<v>.arity() == <arity> && <v>.getName().equals(\"<name>\")";
    }
}

JCode trans(muIsDefinedValue(MuExp exp), JGenie jg)
    = "is_defined_value(<trans(exp, jg)>)";

JCode trans(muGetDefinedValue(MuExp exp, AType atype), JGenie jg)
    = "((<atype2javatype(atype)>)get_defined_value(<trans(exp, jg)>))";

JCode trans(muSize(MuExp exp, AType atype), JGenie jg)
    = "((<atype2javatype(atype)>)<trans(exp, jg)>).length()";
    
JCode trans(muHasField(MuExp exp, AType tp, str fieldName), JGenie jg)
    = "anode_has_field(<trans(exp, jg)>,\"<fieldName>\")"
      when isNodeType(tp);
    
JCode trans(muHasField(MuExp exp, AType tp, str fieldName), JGenie jg)
    = "aadt_has_field(<trans(exp, jg)>,\"<fieldName>\")"
      when  isADTType(tp);

JCode trans(muSubscript(MuExp exp, MuExp idx), JGenie jg){
    return "subject_subscript(<trans(exp, jg)>, <trans2NativeInt(idx, jg)>)";
    //return "((<atype2javatype(atype)>)<trans(exp, jg)>).get(<trans2NativeInt(idx, jg)>)";
}

JCode trans(muIncNativeInt(MuExp var, MuExp exp), JGenie jg)
    = muCon(int n) := exp ? "<trans(var, jg)> += <n>;\n" :  "<trans(var, jg)> += <trans(exp, jg)>;\n";
    
JCode trans(muSubNativeInt(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans2NativeInt(exp1, jg)> - <trans2NativeInt(exp2, jg)>";
    
JCode trans(muAddNativeInt(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans2NativeInt(exp1, jg)> + <trans2NativeInt(exp2, jg)>";
    
JCode trans(muGreaterEqNativeInt(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans2NativeInt(exp1, jg)> \>= <trans2NativeInt(exp2, jg)>";

JCode trans(muLessNativeInt(MuExp exp1, MuExp exp2), JGenie jg)
    = "<trans2NativeInt(exp1, jg)> \< <trans2NativeInt(exp2, jg)>";

JCode trans(muAndNativeBool(MuExp exp1, MuExp exp2), JGenie jg){
    v1 = trans2NativeBool(exp1, jg);
    v2 = trans2NativeBool(exp2, jg);
    return v1 == "true" ? v2
                        : (v2 == "true" ? v1 : "<v1> && <v2>");
}

JCode trans(muNotNativeBool(MuExp exp), JGenie jg){
    v = trans2NativeBool(exp, jg);
    return v == "true" ? "false" : "!<v>";                              
}

JCode trans(muSubList(MuExp lst, MuExp from, MuExp len), JGenie jg)
    = "<trans(lst, jg)>.sublist(<trans(from, jg)>, <trans(len, jg)>)";

// Regular expressions

JCode trans(muRegExpCompile(MuExp regExp, MuExp subject), JGenie jg)
    = "regExpCompile(<trans2NativeStr(regExp, jg)>, <trans2NativeStr(subject, jg)>)";
    
JCode trans(muRegExpBegin(MuExp matcher), JGenie jg)
    = "<trans(matcher, jg)>.start()";
    
JCode trans(muRegExpEnd(MuExp matcher), JGenie jg)
    = "<trans(matcher, jg)>.end()";

JCode trans(muRegExpFind(MuExp matcher), JGenie jg)
    =  "<trans(matcher, jg)>.find()";

JCode trans(muRegExpSetRegion(MuExp matcher, int begin, int end), JGenie jg)
    =  "<trans(matcher, jg)>.region(<begin>, <end>)";

JCode trans(muRegExpGroup(MuExp matcher, int n), JGenie jg)
    = "$VF.string(<trans(matcher, jg)>.group(<n>))";
    
// String templates

JCode trans(muTemplate(str initial), JGenie jg)
    = "new Template($VF, \"<escapeAsJavaString(initial)>\")";

JCode trans(muTemplateBeginIndent(MuExp template, str indent), JGenie jg)
    = "<trans(template, jg)>.beginIndent(\"<indent>\");\n";
    
JCode trans(muTemplateEndIndent(MuExp template, str unindent), JGenie jg)
    = "<trans(template, jg)>.endIndent(\"<escapeAsJavaString(unindent)>\");\n";
    
JCode trans(muTemplateAdd(MuExp template, muCon(str s)), JGenie jg)
    = "<trans(template, jg)>.addStr(\"<escapeAsJavaString(s)>\");\n";
    
JCode trans(muTemplateAdd(MuExp template, str s), JGenie jg){
    if(isEmpty(s)) return "";
    s = replaceAll(s, "\n", "\\n");
    return "<trans(template, jg)>.addStr(\"<escapeAsJavaString(s)>\");\n";
}
    
default JCode trans(muTemplateAdd(MuExp template, MuExp exp), JGenie jg)
    = "<trans(template, jg)>.addVal(<trans(exp,jg)>);\n";

JCode trans(muTemplateClose(MuExp template), JGenie jg)
    = "<trans(template, jg)>.close()";