// Compact semantic data-flow summary for ScooterCheck Phase 2.3.1 (Ghidra headless -postScript).
// Usage: -postScript ExportDataFlowSummary.java /absolute/path/out.dataflow.json
// No full pcode dumps — counts and quality only.
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.RefType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public class ExportDataFlowSummary extends GhidraScript {

    private static final int DEFAULT_MAX_FUNCTIONS = 2500;
    private static final int MAX_INSTR_SCAN = 400;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportDataFlowSummary: need output JSON path");
            return;
        }
        File out = new File(args[0]);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        int maxFns = DEFAULT_MAX_FUNCTIONS;
        String envMax = System.getenv("GHIDRA_MAX_FUNCTIONS");
        if (envMax != null && !envMax.isEmpty()) {
            try {
                maxFns = Math.max(50, Integer.parseInt(envMax.trim()));
            } catch (NumberFormatException ignored) {
            }
        }

        FunctionManager fm = currentProgram.getFunctionManager();
        ReferenceManager rm = currentProgram.getReferenceManager();
        Listing listing = currentProgram.getListing();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        String processor = currentProgram.getLanguage().getLanguageID().getIdAsString();

        List<String> topLimitations = new ArrayList<>();
        topLimitations.add("Compact data-flow summary only — no pcode / SSA dump.");
        topLimitations.add("Memory read/write counts use RefType data refs plus LDR/STR mnemonic fallback.");
        topLimitations.add("parameterCount from Ghidra signature when recovered; otherwise null.");
        topLimitations.add("No activation / unlock sequence reconstruction.");

        StringBuilder sb = new StringBuilder(128 * 1024);
        sb.append("{\n");
        sb.append("  \"schemaVersion\": 1,\n");
        sb.append("  \"tool\": ").append(jsonString("ExportDataFlowSummary")).append(",\n");
        sb.append("  \"program\": ").append(jsonString(currentProgram.getName())).append(",\n");
        sb.append("  \"processor\": ").append(jsonString(processor)).append(",\n");
        sb.append("  \"functions\": [\n");

        int count = 0;
        int truncated = 0;
        FunctionIterator it = fm.getFunctions(true);
        boolean first = true;
        while (it.hasNext() && !monitor.isCancelled()) {
            Function fn = it.next();
            if (fn.isThunk()) {
                continue;
            }
            if (count >= maxFns) {
                truncated++;
                continue;
            }
            try {
                String entry = fn.getEntryPoint().toString();
                String name = fn.getName(false);
                int parameterCount = 0;
                boolean paramKnown = false;
                List<String> limitations = new ArrayList<>();
                try {
                    parameterCount = fn.getParameterCount();
                    paramKnown = true;
                } catch (Exception e) {
                    limitations.add("parameterCount unavailable");
                }

                int memoryReads = 0;
                int memoryWrites = 0;
                int compareOps = 0;
                int conditionalBranches = 0;
                int callCount = 0;
                int dataReferenceCount = 0;
                int mnemonicLoads = 0;
                int mnemonicStores = 0;
                int mnemonicCalls = 0;
                int scanned = 0;
                boolean hasInstr = false;

                try {
                    for (Function callee : fn.getCalledFunctions(monitor)) {
                        if (callee != null) {
                            callCount++;
                        }
                    }
                } catch (Exception ignored) {
                }

                try {
                    Address min = fn.getBody().getMinAddress();
                    Address max = fn.getBody().getMaxAddress();
                    Instruction instr = listing.getInstructionAt(min);
                    while (instr != null && scanned < MAX_INSTR_SCAN) {
                        if (instr.getAddress().compareTo(max) > 0) {
                            break;
                        }
                        if (fn.getBody() != null && !fn.getBody().contains(instr.getAddress())) {
                            break;
                        }
                        hasInstr = true;
                        String low = normMnem(instr.getMnemonicString());
                        if (isCompare(low)) {
                            compareOps++;
                        }
                        if (isConditionalBranch(low)) {
                            conditionalBranches++;
                        }
                        if (isCallMnemonic(low)) {
                            mnemonicCalls++;
                        }
                        if (isLoadMnemonic(low)) {
                            mnemonicLoads++;
                        }
                        if (isStoreMnemonic(low)) {
                            mnemonicStores++;
                        }

                        Reference[] refs = rm.getReferencesFrom(instr.getAddress());
                        if (refs != null) {
                            for (Reference ref : refs) {
                                if (ref == null) {
                                    continue;
                                }
                                RefType rt = ref.getReferenceType();
                                if (rt == null) {
                                    continue;
                                }
                                if (rt.isData()) {
                                    dataReferenceCount++;
                                    if (rt.isRead()) {
                                        memoryReads++;
                                    }
                                    if (rt.isWrite()) {
                                        memoryWrites++;
                                    }
                                }
                            }
                        }

                        instr = instr.getNext();
                        scanned++;
                    }
                } catch (Exception e) {
                    limitations.add("instruction scan partial: " + safeMsg(e));
                }

                // Mnemonic fallback when RefType counts are empty but LDR/STR present.
                if (memoryReads == 0 && mnemonicLoads > 0) {
                    memoryReads = mnemonicLoads;
                    limitations.add("memoryReads from LDR/POP mnemonics");
                }
                if (memoryWrites == 0 && mnemonicStores > 0) {
                    memoryWrites = mnemonicStores;
                    limitations.add("memoryWrites from STR/PUSH mnemonics");
                }
                if (callCount == 0 && mnemonicCalls > 0) {
                    callCount = mnemonicCalls;
                    limitations.add("callCount from BL/BLX mnemonics");
                }
                if (dataReferenceCount == 0 && (memoryReads + memoryWrites) > 0) {
                    dataReferenceCount = memoryReads + memoryWrites;
                }
                if (!hasInstr) {
                    limitations.add("no instructions in body");
                }

                String quality;
                if (hasInstr && scanned > 0) {
                    quality = (memoryReads + memoryWrites + compareOps + callCount) > 0
                        ? "ok" : "partial";
                    if (!paramKnown) {
                        quality = "partial";
                    }
                } else if (callCount > 0) {
                    quality = "partial";
                } else {
                    quality = "missing";
                }

                if (!first) {
                    sb.append(",\n");
                }
                first = false;
                sb.append("    {\n");
                sb.append("      \"address\": ").append(jsonString(entry)).append(",\n");
                sb.append("      \"name\": ").append(jsonString(name)).append(",\n");
                if (paramKnown) {
                    sb.append("      \"parameterCount\": ").append(parameterCount).append(",\n");
                } else {
                    sb.append("      \"parameterCount\": null,\n");
                }
                sb.append("      \"memoryReads\": ").append(memoryReads).append(",\n");
                sb.append("      \"memoryWrites\": ").append(memoryWrites).append(",\n");
                sb.append("      \"compareOps\": ").append(compareOps).append(",\n");
                sb.append("      \"conditionalBranches\": ").append(conditionalBranches).append(",\n");
                sb.append("      \"callCount\": ").append(callCount).append(",\n");
                sb.append("      \"dataReferenceCount\": ").append(dataReferenceCount).append(",\n");
                sb.append("      \"quality\": ").append(jsonString(quality)).append(",\n");
                sb.append("      \"limitations\": ").append(jsonStringArray(limitations)).append("\n");
                sb.append("    }");
                count++;
            } catch (Exception e) {
                printerr("ExportDataFlowSummary skip " + fn.getName() + ": " + e.getMessage());
            }
        }

        if (truncated > 0) {
            topLimitations.add(
                "Export truncated at maxFunctions=" + maxFns + " skipped=" + truncated
            );
        }

        sb.append("\n  ],\n");
        sb.append("  \"functionCount\": ").append(count).append(",\n");
        sb.append("  \"truncated\": ").append(truncated > 0 ? "true" : "false").append(",\n");
        sb.append("  \"truncatedSkipped\": ").append(truncated).append(",\n");
        sb.append("  \"maxFunctions\": ").append(maxFns).append(",\n");
        sb.append("  \"analysisLimitations\": ").append(jsonStringArray(topLimitations)).append("\n");
        sb.append("}\n");

        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write(sb.toString());
        }
        println("ExportDataFlowSummary: " + count + " functions -> " + out.getAbsolutePath()
            + (truncated > 0 ? (" (truncated +" + truncated + ")") : ""));
    }

    private static String normMnem(String mnem) {
        if (mnem == null || mnem.isEmpty()) {
            return "";
        }
        String low = mnem.toLowerCase(Locale.ROOT);
        int dot = low.indexOf('.');
        if (dot > 0) {
            low = low.substring(0, dot);
        }
        return low;
    }

    private static boolean isCompare(String low) {
        return low.equals("cmp") || low.equals("cmn") || low.equals("tst") || low.equals("teq");
    }

    private static boolean isConditionalBranch(String low) {
        if (low.isEmpty()) {
            return false;
        }
        if (low.equals("cbz") || low.equals("cbnz") || low.equals("tbz") || low.equals("tbnz")) {
            return true;
        }
        if (low.startsWith("it")) {
            return true;
        }
        // b<cc> but not b / bx / bl / blx
        if (low.equals("b") || low.equals("bx") || low.equals("bl") || low.equals("blx")) {
            return false;
        }
        if (low.startsWith("b") && low.length() >= 3) {
            char c1 = low.charAt(1);
            if (c1 == 'l' || c1 == 'x') {
                return false; // bl*, bx*
            }
            return true;
        }
        return false;
    }

    private static boolean isCallMnemonic(String low) {
        return low.equals("bl") || low.equals("blx");
    }

    private static boolean isLoadMnemonic(String low) {
        return low.startsWith("ldr") || low.startsWith("ldm") || low.equals("pop")
            || low.startsWith("ldrex");
    }

    private static boolean isStoreMnemonic(String low) {
        return low.startsWith("str") || low.startsWith("stm") || low.equals("push")
            || low.startsWith("strex");
    }

    private static String safeMsg(Exception e) {
        String m = e.getMessage();
        if (m == null) {
            return e.getClass().getSimpleName();
        }
        if (m.length() > 80) {
            return m.substring(0, 80);
        }
        return m;
    }

    private static String jsonString(String s) {
        if (s == null) {
            return "null";
        }
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '\\': b.append("\\\\"); break;
                case '"': b.append("\\\""); break;
                case '\n': b.append("\\n"); break;
                case '\r': b.append("\\r"); break;
                case '\t': b.append("\\t"); break;
                default:
                    if (c < 0x20) {
                        b.append(String.format("\\u%04x", (int) c));
                    } else {
                        b.append(c);
                    }
            }
        }
        b.append('"');
        return b.toString();
    }

    private static String jsonStringArray(List<String> items) {
        StringBuilder b = new StringBuilder("[");
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) {
                b.append(", ");
            }
            b.append(jsonString(items.get(i)));
        }
        b.append("]");
        return b.toString();
    }
}
