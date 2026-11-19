// Structured function inventory for ScooterCheck Phase 2 (Ghidra headless -postScript).
// Usage: -postScript ExportFunctionAnalysis.java /absolute/path/out.functions.json
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.block.BasicBlockModel;
import ghidra.program.model.block.CodeBlock;
import ghidra.program.model.block.CodeBlockIterator;
import ghidra.program.model.block.CodeBlockReference;
import ghidra.program.model.block.CodeBlockReferenceIterator;
import ghidra.program.model.listing.Data;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.FunctionManager;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryAccessException;
import ghidra.program.model.mem.MemoryBlock;
import ghidra.program.model.symbol.RefType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public class ExportFunctionAnalysis extends GhidraScript {

    private static final int DEFAULT_MAX_FUNCTIONS = 2500;
    private static final int MAX_CALLS = 48;
    private static final int MAX_CONSTANTS = 24;
    private static final int MAX_STRINGS = 16;

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportFunctionAnalysis: need output JSON path");
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
        BasicBlockModel bbm = new BasicBlockModel(currentProgram);
        ReferenceManager rm = currentProgram.getReferenceManager();
        Listing listing = currentProgram.getListing();
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        String processor = currentProgram.getLanguage().getLanguageID().getIdAsString();
        Memory mem = currentProgram.getMemory();
        Address actualImageBase = currentProgram.getImageBase();
        String requestedLoaderBase = System.getenv("GHIDRA_BASE_ADDR");
        if (requestedLoaderBase == null || requestedLoaderBase.isEmpty()) {
            requestedLoaderBase = System.getenv("SCOOTERCHECK_LOADER_BASE");
        }
        Address memoryBlockStart = null;
        try {
            for (MemoryBlock block : mem.getBlocks()) {
                if (block != null && block.isInitialized() && block.isLoaded()) {
                    memoryBlockStart = block.getStart();
                    break;
                }
            }
        } catch (Exception ignored) {
        }
        // Prefer IVT at memory block start (BinaryLoader maps here) over ImageBase which may stay 0.
        Address ivtProbe = memoryBlockStart != null ? memoryBlockStart : actualImageBase;
        String resetHandlerAddress = null;
        Long resetHandlerFileOffset = null;
        try {
            int sp = mem.getInt(ivtProbe);
            int resetWord = mem.getInt(ivtProbe.add(4));
            long resetDest = (resetWord & 0xFFFFFFFFL) & ~1L;
            resetHandlerAddress = String.format("0x%08x", resetDest);
            if (memoryBlockStart != null) {
                resetHandlerFileOffset = Long.valueOf(resetDest - memoryBlockStart.getOffset());
            }
            // silence unused warning for sp read (validates IVT readable)
            if (sp == 0) {
                // keep nulls if clearly empty
            }
        } catch (Exception ignored) {
        }

        StringBuilder sb = new StringBuilder(256 * 1024);
        sb.append("{\n");
        sb.append("  \"schemaVersion\": 1,\n");
        // featuresVersion documents optional fields (branchMnemonicCount) without
        // changing fingerprint semantics (analyzerCompat stays "2").
        sb.append("  \"featuresVersion\": 2,\n");
        sb.append("  \"program\": ").append(jsonString(currentProgram.getName())).append(",\n");
        sb.append("  \"processor\": ").append(jsonString(processor)).append(",\n");
        // Phase 2.2G: distinguish requested loader base vs Ghidra ImageBase vs memory block.
        // BinaryLoader often maps the file at loader-baseAddr while getImageBase() stays 0.
        sb.append("  \"imageBase\": ").append(jsonString(actualImageBase.toString())).append(",\n");
        sb.append("  \"actualImageBase\": ").append(jsonString(actualImageBase.toString())).append(",\n");
        if (requestedLoaderBase != null && !requestedLoaderBase.isEmpty()) {
            sb.append("  \"requestedLoaderBase\": ").append(jsonString(requestedLoaderBase)).append(",\n");
        } else {
            sb.append("  \"requestedLoaderBase\": null,\n");
        }
        if (memoryBlockStart != null) {
            sb.append("  \"memoryBlockStart\": ").append(jsonString(memoryBlockStart.toString())).append(",\n");
        } else {
            sb.append("  \"memoryBlockStart\": null,\n");
        }
        if (resetHandlerAddress != null) {
            sb.append("  \"resetHandlerAddress\": ").append(jsonString(resetHandlerAddress)).append(",\n");
        } else {
            sb.append("  \"resetHandlerAddress\": null,\n");
        }
        if (resetHandlerFileOffset != null) {
            sb.append("  \"firmwareFileOffset\": ").append(resetHandlerFileOffset.longValue()).append(",\n");
        } else {
            sb.append("  \"firmwareFileOffset\": null,\n");
        }
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
                long size = fn.getBody() != null ? fn.getBody().getNumAddresses() : 0;
                int blocks = 0;
                int edges = 0;
                try {
                    CodeBlockIterator bit = bbm.getCodeBlocksContaining(fn.getBody(), monitor);
                    while (bit.hasNext() && !monitor.isCancelled()) {
                        CodeBlock block = bit.next();
                        blocks++;
                        CodeBlockReferenceIterator dest = block.getDestinations(monitor);
                        while (dest.hasNext()) {
                            dest.next();
                            edges++;
                        }
                    }
                } catch (Exception e) {
                    // keep zeros
                }

                List<String> calls = new ArrayList<>();
                Set<String> callSet = new HashSet<>();
                try {
                    for (Function callee : fn.getCalledFunctions(monitor)) {
                        if (callee == null) {
                            continue;
                        }
                        String n = callee.getName(false);
                        if (callSet.add(n) && calls.size() < MAX_CALLS) {
                            calls.add(n);
                        }
                    }
                } catch (Exception ignored) {
                }

                List<String> calledBy = new ArrayList<>();
                Set<String> bySet = new HashSet<>();
                try {
                    for (Function caller : fn.getCallingFunctions(monitor)) {
                        if (caller == null) {
                            continue;
                        }
                        String n = caller.getName(false);
                        if (bySet.add(n) && calledBy.size() < MAX_CALLS) {
                            calledBy.add(n);
                        }
                    }
                } catch (Exception ignored) {
                }

                List<String> constants = new ArrayList<>();
                List<String> strings = new ArrayList<>();
                collectRefs(fn, listing, constants, strings);
                List<String> mnemonics = collectMnemonics(fn, listing);
                int branchMnemonics = countBranchMnemonics(mnemonics);

                Collections.sort(calls);
                Collections.sort(calledBy);
                Collections.sort(constants);
                Collections.sort(strings);

                String fingerprint = fingerprint(size, blocks, edges, calls, constants, mnemonics);
                String confidence = (blocks > 0 && size > 0) ? "medium" : "low";

                if (!first) {
                    sb.append(",\n");
                }
                first = false;
                sb.append("    {\n");
                sb.append("      \"address\": ").append(jsonString(entry)).append(",\n");
                sb.append("      \"name\": ").append(jsonString(fn.getName(false))).append(",\n");
                sb.append("      \"size\": ").append(size).append(",\n");
                sb.append("      \"basicBlocks\": ").append(blocks).append(",\n");
                sb.append("      \"cfgEdges\": ").append(edges).append(",\n");
                sb.append("      \"calls\": ").append(jsonStringArray(calls)).append(",\n");
                sb.append("      \"calledBy\": ").append(jsonStringArray(calledBy)).append(",\n");
                sb.append("      \"constants\": ").append(jsonStringArray(constants)).append(",\n");
                sb.append("      \"strings\": ").append(jsonStringArray(strings)).append(",\n");
                sb.append("      \"mnemonics\": ").append(jsonStringArray(mnemonics)).append(",\n");
                // Phase 2.2C: optional structural hints (do not affect fingerprint).
                sb.append("      \"branchMnemonicCount\": ").append(branchMnemonics).append(",\n");
                sb.append("      \"fingerprint\": ").append(jsonString(fingerprint)).append(",\n");
                sb.append("      \"confidence\": ").append(jsonString(confidence)).append(",\n");
                sb.append("      \"processor\": ").append(jsonString(processor)).append(",\n");
                sb.append("      \"quality\": ").append(jsonString(blocks > 0 ? "cfg-ok" : "partial")).append("\n");
                sb.append("    }");
                count++;
            } catch (Exception e) {
                printerr("ExportFunctionAnalysis skip " + fn.getName() + ": " + e.getMessage());
            }
        }

        sb.append("\n  ],\n");
        sb.append("  \"functionCount\": ").append(count).append(",\n");
        sb.append("  \"truncated\": ").append(truncated > 0 ? "true" : "false").append(",\n");
        sb.append("  \"truncatedSkipped\": ").append(truncated).append(",\n");
        sb.append("  \"maxFunctions\": ").append(maxFns).append("\n");
        sb.append("}\n");

        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write(sb.toString());
        }
        println("ExportFunctionAnalysis: " + count + " functions -> " + out.getAbsolutePath()
            + (truncated > 0 ? (" (truncated +" + truncated + ")") : ""));
    }

    private void collectRefs(
        Function fn,
        Listing listing,
        List<String> constants,
        List<String> strings
    ) {
        Set<String> cset = new HashSet<>();
        Set<String> sset = new HashSet<>();
        try {
            Address min = fn.getBody().getMinAddress();
            Address max = fn.getBody().getMaxAddress();
            Instruction instr = listing.getInstructionAt(min);
            int scanned = 0;
            while (instr != null && scanned < 400) {
                if (instr.getAddress().compareTo(max) > 0) {
                    break;
                }
                String imm = instr.toString();
                int idx = imm.toLowerCase(Locale.ROOT).indexOf("0x");
                while (idx >= 0 && constants.size() < MAX_CONSTANTS) {
                    int end = idx + 2;
                    while (end < imm.length()) {
                        char ch = imm.charAt(end);
                        if ((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f') || (ch >= 'A' && ch <= 'F')) {
                            end++;
                        } else {
                            break;
                        }
                    }
                    String hex = imm.substring(idx, end).toLowerCase(Locale.ROOT);
                    if (hex.length() >= 4 && cset.add(hex)) {
                        constants.add(hex);
                    }
                    idx = imm.toLowerCase(Locale.ROOT).indexOf("0x", end);
                }
                // String data referenced from this instruction.
                // Ghidra 12.x: getReferencesFrom returns Reference[] (not ReferenceIterator).
                Reference[] refs = currentProgram.getReferenceManager().getReferencesFrom(instr.getAddress());
                if (refs != null) {
                    for (Reference ref : refs) {
                        if (ref == null || !ref.getReferenceType().isData()) {
                            continue;
                        }
                        Data data = listing.getDataAt(ref.getToAddress());
                        if (data != null && data.hasStringValue()) {
                            Object v = data.getValue();
                            if (v != null) {
                                String s = String.valueOf(v);
                                if (s.length() >= 3 && s.length() <= 80 && sset.add(s) && strings.size() < MAX_STRINGS) {
                                    strings.add(s);
                                }
                            }
                        }
                    }
                }
                instr = instr.getNext();
                scanned++;
            }
        } catch (Exception ignored) {
        }
    }

    private List<String> collectMnemonics(Function fn, Listing listing) {
        List<String> out = new ArrayList<>();
        try {
            Instruction instr = listing.getInstructionAt(fn.getEntryPoint());
            int scanned = 0;
            while (instr != null && scanned < 256) {
                if (fn.getBody() != null && !fn.getBody().contains(instr.getAddress())) {
                    break;
                }
                String m = instr.getMnemonicString();
                if (m != null && !m.isEmpty()) {
                    out.add(m.toLowerCase(Locale.ROOT));
                }
                instr = instr.getNext();
                scanned++;
            }
        } catch (Exception ignored) {
        }
        return out;
    }

    private static int countBranchMnemonics(List<String> mnemonics) {
        int n = 0;
        for (String m : mnemonics) {
            if (m == null || m.isEmpty()) {
                continue;
            }
            String low = m.toLowerCase(Locale.ROOT);
            if (low.startsWith("b") || low.startsWith("cbz") || low.startsWith("cbnz")
                || low.startsWith("tbz") || low.startsWith("tbnz") || low.equals("it")) {
                n++;
            }
        }
        return n;
    }

    private static String fingerprint(
        long size,
        int blocks,
        int edges,
        List<String> calls,
        List<String> constants,
        List<String> mnemonics
    ) {
        try {
            MessageDigest md = MessageDigest.getInstance("SHA-256");
            // Structural fingerprint: CFG + call names + mnemonic sequence.
            // Exclude auto-names and absolute code addresses so identical logic at
            // different offsets can still match; mnemonics avoid leaf collisions.
            List<String> structuralConstants = new ArrayList<>();
            for (String c : constants) {
                if (c == null) {
                    continue;
                }
                String low = c.toLowerCase(Locale.ROOT);
                if (looksLikeCodeAddress(low)) {
                    continue;
                }
                structuralConstants.add(low);
            }
            Collections.sort(structuralConstants);
            List<String> sortedCalls = new ArrayList<>(calls);
            Collections.sort(sortedCalls);
            String payload = size + "|" + blocks + "|" + edges + "|"
                + String.join(",", sortedCalls) + "|" + String.join(",", structuralConstants)
                + "|" + String.join(",", mnemonics);
            byte[] dig = md.digest(payload.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(16);
            for (int i = 0; i < 8; i++) {
                hex.append(String.format("%02x", dig[i]));
            }
            return hex.toString();
        } catch (Exception e) {
            return "unknown";
        }
    }

    /** Filter PC-relative literal pool targets / image addresses from fingerprints. */
    private static boolean looksLikeCodeAddress(String hexImm) {
        if (hexImm == null) {
            return false;
        }
        String h = hexImm.startsWith("0x") ? hexImm.substring(2) : hexImm;
        if (h.length() < 6 || h.length() > 16) {
            return false;
        }
        // Cortex-M flash / SRAM style immediates commonly appear in LDR literals.
        return h.startsWith("08") || h.startsWith("20") || h.startsWith("080") || h.startsWith("200");
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
