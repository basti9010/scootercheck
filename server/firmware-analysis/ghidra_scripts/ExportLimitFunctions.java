// Decompile only functions that reference known packed speed immediates (+ 1 caller level).
// Produces a focused .limits.c for combo/LLM analysis — higher signal than full dump.
// Usage: -postScript ExportLimitFunctions.java /absolute/path/out.limits.c
//@category ScooterCheck

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.InstructionIterator;
import ghidra.program.model.scalar.Scalar;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Iterator;
import java.util.Set;

public class ExportLimitFunctions extends GhidraScript {

    private static final long[] KNOWN = {
        0x1400, 0x1600, 0x1700, 0x1900, 0x1E00, 0x2000,
        0x2300, 0x2319, 0x2800, 0x2D00, 0x3200, 0x6300
    };

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportLimitFunctions: need output .limits.c path");
            return;
        }
        File out = new File(args[0]);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        Set<Long> known = new HashSet<>();
        for (long k : KNOWN) {
            known.add(k);
        }

        FunctionManager fm = currentProgram.getFunctionManager();
        Set<Function> targets = new HashSet<>();

        InstructionIterator it = currentProgram.getListing().getInstructions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Instruction insn = it.next();
            int n = insn.getNumOperands();
            for (int i = 0; i < n; i++) {
                Object[] objs = insn.getOpObjects(i);
                if (objs == null) {
                    continue;
                }
                for (Object o : objs) {
                    if (!(o instanceof Scalar)) {
                        continue;
                    }
                    long v = ((Scalar) o).getUnsignedValue() & 0xFFFFL;
                    if (!known.contains(v)) {
                        continue;
                    }
                    Function fn = fm.getFunctionContaining(insn.getAddress());
                    if (fn != null) {
                        targets.add(fn);
                    }
                }
            }
        }

        // One caller level (incoming)
        Set<Function> withCallers = new HashSet<>(targets);
        for (Function fn : targets) {
            try {
                Iterator<Function> callers = fn.getCallingFunctions(monitor).iterator();
                int added = 0;
                while (callers.hasNext() && added < 4) {
                    withCallers.add(callers.next());
                    added++;
                }
            } catch (Exception ignored) {
            }
        }

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);
        ConsoleTaskMonitor mon = new ConsoleTaskMonitor();

        int ok = 0;
        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write("/* ScooterCheck focused decompile: functions touching packed speed immediates */\n");
            w.write("/* functions=" + withCallers.size() + " seed=" + targets.size() + " */\n\n");
            for (Function fn : withCallers) {
                if (monitor.isCancelled()) {
                    break;
                }
                try {
                    DecompileResults res = decomp.decompileFunction(fn, 90, mon);
                    if (NoneOrFailed(res)) {
                        w.write("/* FAIL " + fn.getName() + " @ " + fn.getEntryPoint() + " */\n\n");
                        continue;
                    }
                    String c = res.getDecompiledFunction().getC();
                    w.write("/* ==== " + fn.getName() + " @ " + fn.getEntryPoint() + " ==== */\n");
                    w.write(c);
                    w.write("\n\n");
                    ok++;
                } catch (Exception e) {
                    w.write("/* ERR " + fn.getName() + ": " + e.getMessage() + " */\n\n");
                }
            }
        }
        decomp.dispose();
        println("ExportLimitFunctions: decompiled " + ok + "/" + withCallers.size() + " -> " + out.getAbsolutePath());
    }

    private static boolean NoneOrFailed(DecompileResults res) {
        return res == null || !res.decompileCompleted() || res.getDecompiledFunction() == null;
    }
}
