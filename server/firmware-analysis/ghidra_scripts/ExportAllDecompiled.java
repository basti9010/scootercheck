// Export all decompiled functions to a single .c file (Ghidra headless -postScript).
// Usage: -postScript ExportAllDecompiled.java /absolute/path/out.c
//@category ScooterCheck

import ghidra.app.decompiler.DecompInterface;
import ghidra.app.decompiler.DecompileResults;
import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;

public class ExportAllDecompiled extends GhidraScript {

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportAllDecompiled: need output path argument");
            return;
        }
        File out = new File(args[0]);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        DecompInterface decomp = new DecompInterface();
        decomp.openProgram(currentProgram);

        int count = 0;
        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write("/* ScooterCheck Ghidra export: " + currentProgram.getName() + " */\n\n");
            FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
            ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
            while (it.hasNext() && !monitor.isCancelled()) {
                Function fn = it.next();
                if (fn.isThunk()) {
                    continue;
                }
                DecompileResults res = decomp.decompileFunction(fn, 60, monitor);
                if (res == null || res.getDecompiledFunction() == null) {
                    w.write("/* FAILED: " + fn.getName() + " @ " + fn.getEntryPoint() + " */\n\n");
                    continue;
                }
                w.write(res.getDecompiledFunction().getC());
                w.write("\n\n");
                count++;
            }
        } finally {
            decomp.dispose();
        }
        println("ExportAllDecompiled: wrote " + count + " functions -> " + out.getAbsolutePath());
    }
}
