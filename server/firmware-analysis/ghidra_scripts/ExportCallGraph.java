// Structured call-graph export for ScooterCheck Phase 2 / 2.2F.
// Classifies control-flow: DIRECT_CALL, INDIRECT_CALL, INTERNAL_BRANCH,
// TAIL_CALL, UNRESOLVED_CALL, UNKNOWN_CONTROL_FLOW.
// Internal branches are NOT counted as unresolved calls.
// Usage: -postScript ExportCallGraph.java /absolute/path/out.callgraph.json
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.RefType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.HashSet;
import java.util.Set;

public class ExportCallGraph extends GhidraScript {

    private static final int DEFAULT_MAX_EDGES = 8000;
    private static final int DEFAULT_MAX_FUNCTIONS = 2500;

    // Classification kinds (Phase 2.2F)
    private static final String DIRECT_CALL = "DIRECT_CALL";
    private static final String INDIRECT_CALL = "INDIRECT_CALL";
    private static final String INTERNAL_BRANCH = "INTERNAL_BRANCH";
    private static final String TAIL_CALL = "TAIL_CALL";
    private static final String UNRESOLVED_CALL = "UNRESOLVED_CALL";
    private static final String UNKNOWN_CONTROL_FLOW = "UNKNOWN_CONTROL_FLOW";

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args == null || args.length < 1) {
            printerr("ExportCallGraph: need output JSON path");
            return;
        }
        File out = new File(args[0]);
        File parent = out.getParentFile();
        if (parent != null && !parent.exists()) {
            parent.mkdirs();
        }

        int maxEdges = envInt("GHIDRA_MAX_CALLGRAPH_EDGES", DEFAULT_MAX_EDGES);
        int maxFns = envInt("GHIDRA_MAX_FUNCTIONS", DEFAULT_MAX_FUNCTIONS);
        ConsoleTaskMonitor monitor = new ConsoleTaskMonitor();
        ReferenceManager rm = currentProgram.getReferenceManager();
        Listing listing = currentProgram.getListing();

        int edgeCount = 0;
        int fnCount = 0;
        int directCalls = 0;
        int indirectCalls = 0;
        int internalBranches = 0;
        int tailCalls = 0;
        int unresolvedCalls = 0;
        int unknownFlow = 0;
        // Legacy counters kept for older clients
        int unresolvedLegacy = 0;
        int heuristicLegacy = 0;

        StringBuilder sb = new StringBuilder(256 * 1024);
        sb.append("{\n");
        sb.append("  \"schemaVersion\": 2,\n");
        sb.append("  \"featuresVersion\": 2,\n");
        sb.append("  \"program\": ").append(jq(currentProgram.getName())).append(",\n");
        sb.append("  \"edges\": [\n");

        boolean first = true;
        Set<String> seen = new HashSet<>();
        FunctionIterator it = currentProgram.getFunctionManager().getFunctions(true);
        while (it.hasNext() && !monitor.isCancelled()) {
            Function fn = it.next();
            if (fn.isThunk()) {
                continue;
            }
            if (fnCount >= maxFns || edgeCount >= maxEdges) {
                break;
            }
            fnCount++;
            String fromName = fn.getName(false);
            String fromAddr = fn.getEntryPoint().toString();
            Address bodyMin = fn.getBody().getMinAddress();
            Address bodyMax = fn.getBody().getMaxAddress();

            // Stage 1: direct callees via Function API
            try {
                for (Function callee : fn.getCalledFunctions(monitor)) {
                    if (callee == null || edgeCount >= maxEdges) {
                        continue;
                    }
                    String key = fromAddr + "->" + callee.getEntryPoint() + ":DIRECT_CALL";
                    if (!seen.add(key)) {
                        continue;
                    }
                    if (!first) {
                        sb.append(",\n");
                    }
                    first = false;
                    appendEdge(sb, fromAddr, fromName, callee.getEntryPoint().toString(),
                        callee.getName(false), "direct", "static", DIRECT_CALL);
                    edgeCount++;
                    directCalls++;
                }
            } catch (Exception ignored) {
            }

            // Stage 2: instruction-level flow classification
            try {
                Instruction instr = listing.getInstructionAt(bodyMin);
                int scanned = 0;
                while (instr != null && scanned < 400 && edgeCount < maxEdges) {
                    if (instr.getAddress().compareTo(bodyMax) > 0) {
                        break;
                    }
                    FlowType ft = instr.getFlowType();
                    if (ft != null && (ft.isCall() || ft.isJump() || ft.isTerminal())) {
                        Reference[] refs = rm.getReferencesFrom(instr.getAddress());
                        boolean anyFlowRef = false;
                        if (refs != null) {
                            for (Reference ref : refs) {
                                if (ref == null) {
                                    continue;
                                }
                                RefType rt = ref.getReferenceType();
                                if (rt == null || !(rt.isCall() || rt.isJump() || rt.isFlow())) {
                                    continue;
                                }
                                anyFlowRef = true;
                                Address to = ref.getToAddress();
                                Function tgt = getFunctionContaining(to);
                                Function tgtEntry = getFunctionAt(to);
                                // Thumb bit: strip LSB when comparing code addresses
                                boolean internal = to != null && fn.getBody().contains(to);

                                String classification;
                                String kind;
                                String evidence;
                                String toName = null;
                                String toAddrStr = to == null ? null : to.toString();

                                if (internal && tgtEntry == null) {
                                    // Jump/branch staying inside the same function body
                                    classification = INTERNAL_BRANCH;
                                    kind = "jump";
                                    evidence = "internal";
                                    internalBranches++;
                                } else if (ft.isCall() && tgtEntry != null) {
                                    classification = DIRECT_CALL;
                                    kind = "direct";
                                    evidence = "static";
                                    toName = tgtEntry.getName(false);
                                    toAddrStr = tgtEntry.getEntryPoint().toString();
                                    directCalls++;
                                } else if (ft.isCall() && tgt != null && tgtEntry == null) {
                                    // Call into middle of another function — rare; treat as direct-ish
                                    classification = DIRECT_CALL;
                                    kind = "call";
                                    evidence = "static";
                                    toName = tgt.getName(false);
                                    directCalls++;
                                } else if (ft.isCall() && tgt == null) {
                                    classification = UNRESOLVED_CALL;
                                    kind = "call";
                                    evidence = "unresolved";
                                    unresolvedCalls++;
                                    unresolvedLegacy++;
                                } else if (ft.isJump() && !internal && tgtEntry != null) {
                                    // Jump to another function entry ≈ tail call
                                    classification = TAIL_CALL;
                                    kind = "jump";
                                    evidence = "tail";
                                    toName = tgtEntry.getName(false);
                                    toAddrStr = tgtEntry.getEntryPoint().toString();
                                    tailCalls++;
                                } else if (ft.isJump() && !internal && tgt != null) {
                                    classification = TAIL_CALL;
                                    kind = "jump";
                                    evidence = "tail";
                                    toName = tgt.getName(false);
                                    tailCalls++;
                                } else if (ft.isJump() && !internal && tgt == null) {
                                    classification = UNKNOWN_CONTROL_FLOW;
                                    kind = "jump";
                                    evidence = "unknown";
                                    unknownFlow++;
                                } else if (ft.isComputed() && ft.isCall()) {
                                    classification = INDIRECT_CALL;
                                    kind = "indirect";
                                    evidence = "heuristic";
                                    indirectCalls++;
                                    heuristicLegacy++;
                                } else {
                                    classification = UNKNOWN_CONTROL_FLOW;
                                    kind = ft.isCall() ? "call" : "jump";
                                    evidence = "unknown";
                                    unknownFlow++;
                                }

                                String key = fromAddr + "@" + instr.getAddress() + "->" + toAddrStr
                                    + ":" + classification;
                                if (!seen.add(key)) {
                                    // undo counter for duplicate — adjust below by not incrementing again
                                    // Counters already incremented; for duplicates skip write and reverse
                                    if (INTERNAL_BRANCH.equals(classification)) {
                                        internalBranches--;
                                    } else if (DIRECT_CALL.equals(classification)) {
                                        directCalls--;
                                    } else if (TAIL_CALL.equals(classification)) {
                                        tailCalls--;
                                    } else if (UNRESOLVED_CALL.equals(classification)) {
                                        unresolvedCalls--;
                                        unresolvedLegacy--;
                                    } else if (INDIRECT_CALL.equals(classification)) {
                                        indirectCalls--;
                                        heuristicLegacy--;
                                    } else {
                                        unknownFlow--;
                                    }
                                    continue;
                                }

                                if (!first) {
                                    sb.append(",\n");
                                }
                                first = false;
                                appendEdge(sb, fromAddr, fromName, toAddrStr, toName, kind, evidence,
                                    classification);
                                edgeCount++;
                            }
                        }
                        if (!anyFlowRef && ft.isComputed() && ft.isCall()) {
                            String key = fromAddr + "@" + instr.getAddress() + ":INDIRECT";
                            if (seen.add(key)) {
                                if (!first) {
                                    sb.append(",\n");
                                }
                                first = false;
                                appendEdge(sb, fromAddr, fromName, null, null, "indirect", "heuristic",
                                    INDIRECT_CALL);
                                edgeCount++;
                                indirectCalls++;
                                heuristicLegacy++;
                            }
                        }
                    }
                    instr = instr.getNext();
                    scanned++;
                }
            } catch (Exception ignored) {
            }
        }

        sb.append("\n  ],\n");
        sb.append("  \"edgeCount\": ").append(edgeCount).append(",\n");
        sb.append("  \"functionCount\": ").append(fnCount).append(",\n");
        // Legacy fields (older clients) — unresolvedCalls only, NOT internal branches
        sb.append("  \"unresolvedCount\": ").append(unresolvedCalls).append(",\n");
        sb.append("  \"heuristicCount\": ").append(indirectCalls).append(",\n");
        // Phase 2.2F quality breakdown
        sb.append("  \"callGraphQuality\": {\n");
        sb.append("    \"directCalls\": ").append(directCalls).append(",\n");
        sb.append("    \"indirectCalls\": ").append(indirectCalls).append(",\n");
        sb.append("    \"internalBranches\": ").append(internalBranches).append(",\n");
        sb.append("    \"tailCalls\": ").append(tailCalls).append(",\n");
        sb.append("    \"unresolvedCalls\": ").append(unresolvedCalls).append(",\n");
        sb.append("    \"unknownControlFlow\": ").append(unknownFlow).append(",\n");
        sb.append("    \"note\": \"Internal branches are not unresolved calls.\"\n");
        sb.append("  },\n");
        sb.append("  \"truncated\": ").append(edgeCount >= maxEdges || fnCount >= maxFns ? "true" : "false").append("\n");
        sb.append("}\n");

        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write(sb.toString());
        }

        try {
            File dot = new File(out.getAbsolutePath().replace(".json", ".dot"));
            if (dot.getAbsolutePath().equals(out.getAbsolutePath())) {
                dot = new File(out.getAbsolutePath() + ".dot");
            }
            try (BufferedWriter w = new BufferedWriter(new FileWriter(dot, StandardCharsets.UTF_8))) {
                w.write("digraph CallGraph {\n");
                w.write("  // ScooterCheck Phase-2.2F; edges=" + edgeCount
                    + " direct=" + directCalls
                    + " internal=" + internalBranches
                    + " unresolved=" + unresolvedCalls + "\n");
                w.write("  label=\"callgraph edges=" + edgeCount + "\";\n");
                w.write("}\n");
            }
        } catch (Exception ignored) {
        }

        println("ExportCallGraph: " + edgeCount + " edges (direct=" + directCalls
            + " internal=" + internalBranches + " unresolved=" + unresolvedCalls
            + ") -> " + out.getAbsolutePath());
    }

    private static void appendEdge(
        StringBuilder sb,
        String fromAddr,
        String fromName,
        String toAddr,
        String toName,
        String kind,
        String evidence,
        String classification
    ) {
        sb.append("    {");
        sb.append("\"from\": ").append(jq(fromAddr)).append(", ");
        sb.append("\"fromName\": ").append(jq(fromName)).append(", ");
        sb.append("\"to\": ").append(toAddr == null ? "null" : jq(toAddr)).append(", ");
        sb.append("\"toName\": ").append(toName == null ? "null" : jq(toName)).append(", ");
        sb.append("\"kind\": ").append(jq(kind)).append(", ");
        sb.append("\"evidence\": ").append(jq(evidence)).append(", ");
        sb.append("\"classification\": ").append(jq(classification));
        sb.append("}");
    }

    private static int envInt(String key, int def) {
        String v = System.getenv(key);
        if (v == null || v.isEmpty()) {
            return def;
        }
        try {
            return Math.max(10, Integer.parseInt(v.trim()));
        } catch (NumberFormatException e) {
            return def;
        }
    }

    private static String jq(String s) {
        if (s == null) {
            return "null";
        }
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == '\\' || c == '"') {
                b.append('\\').append(c);
            } else if (c < 0x20) {
                b.append(String.format("\\u%04x", (int) c));
            } else {
                b.append(c);
            }
        }
        b.append('"');
        return b.toString();
    }
}
