#lang pyret

import cmdline as C
import file as F
import exec as X
import string-dict as D
import "./compile.arr" as CM
import "./compile-structs.arr" as CS


fun main(args):
  options = {
    compile-standalone-js:
      C.next-val(C.String, C.once, "Pyret (.arr) file to compile"),
    compile-module-js:
      C.next-val(C.String, C.once, "Pyret (.arr) file to compile"),
    library:
      C.flag(C.once, "Don't auto-import basics like list, option, etc."),
    libs:
      C.next-val(C.String, C.many, "Paths to files to include as builtin libraries"),
    module-load-dir:
      C.next-val(C.String, C.once, "Base directory to search for modules"),
    check-all:
      C.flag(C.once, "Run checks all modules (not just the main module)"),
    no-check-mode:
      C.flag(C.once, "Skip checks"),
    allow-shadow:
      C.flag(C.once, "Run without checking for shadowed variables")
  }
  
  params-parsed = C.parse-args(options, args)

  fun err-main-loc(e :: CS.CompileError):
    cases(CS.CompileError) e:
      | wf-err(_, l) => l
      | wf-err-split(_, ls) => ls.first
      | unbound-var(_, l) => l
      | pointless-var(l) => l
      | pointless-shadow(l) => l
      | bad-assignment(_, l, _) => l
      | mixed-id-var(_, l1, l2) => if l1.before(l2): l1 else: l2 end
      | shadow-id(_, l, _) => l
      | duplicate-id(_, l, _) => l
    end
  end
  fun err-less(e1 :: CS.CompileError, e2 :: CS.CompileError):
    err-main-loc(e1).before(err-main-loc(e2)) or
    ((err-main-loc(e1) == err-main-loc(e2)) and (tostring(e1) < tostring(e2)))
  end
  
  cases(C.ParsedArguments) params-parsed:
    | success(r, rest) => 
      check-mode = not (r.has-key("no-check-mode") or r.has-key("library"))
      allow-shadowed = r.has-key("allow-shadow")
      libs = if r.has-key("library"): CS.minimal-builtins else: CS.standard-builtins end
      module-dir = if r.has-key("module-load-dir"): r.get("module-load-dir") else: "." end
      check-all = r.has-key("check-all")
      if not is-empty(rest):
        program-name = rest.first
        result = CM.compile-js(
          F.file-to-string(program-name),
          program-name,
          libs,
          {
            check-mode : check-mode,
            allow-shadowed : allow-shadowed
          }
          )
        cases(CS.CompileResult) result:
          | ok(comp-object) =>
            exec-result = X.exec(comp-object.pyret-to-js-runnable(), program-name, module-dir, check-all, rest)
            if (exec-result.success): print(exec-result.render-check-results())
            else: print(exec-result.failure)
            end
          | err(errors) =>
            print-error("Compilation errors:")
            for list.each(e from errors.sort-by(err-less, _ == _)):
              print-error(tostring(e))
            end
            result
        end
      else:
        result = if r.has-key("compile-standalone-js"):
          CM.compile-standalone-js-file(
            r.get("compile-standalone-js"),
            libs,
            {
              check-mode : check-mode,
              allow-shadowed : allow-shadowed
            }
            )
        else if r.has-key("compile-module-js"):
          CM.compile-js(
            F.file-to-string(r.get("compile-module-js")),
            r.get("compile-module-js"),
            libs,
            {
              check-mode : check-mode,
              allow-shadowed : allow-shadowed
            }
            )
        else:
          print(C.usage-info(options).join-str("\n"))
          raise("Unknown command line options")
        end
        cases(CS.CompileResult) result:
          | ok(comp-object) => comp-object.print-js-runnable(display)
          | err(errors) =>
            print-error("Compilation errors:")
            for list.each(e from errors.sort-by(err-less, _ == _)):
              print-error(tostring(e))
            end
            result
        end
      end
    | arg-error(message, partial) =>
      print(message)
      print(C.usage-info(options).join-str("\n"))
  end
end

_ = main(C.args)
