// Structured call-graph export for ScooterCheck Phase 2.
// Usage: -postScript ExportCallGraph.java /absolute/path/out.callgraph.json
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.FunctionIterator;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.listing.Listing;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.ReferenceManager;
import ghidra.util.task.ConsoleTaskMonitor;

import java.io.BufferedWriter;
import java.io.File;
import java.io.FileWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class ExportCallGraph extends GhidraScript {

    private static final int DEFAULT_MAX_EDGES = 8000;
    private static final int DEFAULT_MAX_FUNCTIONS = 2500;

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

        StringBuilder sb = new StringBuilder(128 * 1024);
        sb.append("{\n");
        sb.append("  \"schemaVersion\": 1,\n");
        sb.append("  \"program\": ").append(jq(currentProgram.getName())).append(",\n");
        sb.append("  \"edges\": [\n");

        int edgeCount = 0;
        int unresolved = 0;
        int heuristic = 0;
        int fnCount = 0;
        boolean first = true;
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

            // Direct calls via Function API (static).
            try {
                for (Function callee : fn.getCalledFunctions(monitor)) {
                    if (callee == null || edgeCount >= maxEdges) {
                        continue;
                    }
                    if (!first) {
                        sb.append(",\n");
                    }
                    first = false;
                    appendEdge(sb, fromAddr, fromName, callee.getEntryPoint().toString(),
                        callee.getName(false), "direct", "static");
                    edgeCount++;
                }
            } catch (Exception ignored) {
            }

            // Scan instructions for unresolved / indirect flow.
            try {
                Instruction instr = listing.getInstructionAt(fn.getBody().getMinAddress());
                int scanned = 0;
                while (instr != null && scanned < 300 && edgeCount < maxEdges) {
                    if (instr.getAddress().compareTo(fn.getBody().getMaxAddress()) > 0) {
                        break;
                    }
                    FlowType ft = instr.getFlowType();
                    if (ft != null && (ft.isCall() || ft.isJump())) {
                        // Ghidra 12.x: getReferencesFrom returns Reference[] (not ReferenceIterator).
                        Reference[] refs = rm.getReferencesFrom(instr.getAddress());
                        boolean any = false;
                        if (refs != null) {
                            for (Reference ref : refs) {
                                if (ref == null) {
                                    continue;
                                }
                                any = true;
                                Function tgt = getFunctionAt(ref.getToAddress());
                                if (tgt == null) {
                                    if (!first) {
                                        sb.append(",\n");
                                    }
                                    first = false;
                                    appendEdge(sb, fromAddr, fromName, ref.getToAddress().toString(),
                                        null, ft.isCall() ? "call" : "jump", "unresolved");
                                    edgeCount++;
                                    unresolved++;
                                }
                            }
                        }
                        if (!any && ft.isComputed()) {
                            if (!first) {
                                sb.append(",\n");
                            }
                            first = false;
                            appendEdge(sb, fromAddr, fromName, null, null,
                                "indirect", "heuristic");
                            edgeCount++;
                            heuristic++;
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
        sb.append("  \"unresolvedCount\": ").append(unresolved).append(",\n");
        sb.append("  \"heuristicCount\": ").append(heuristic).append(",\n");
        sb.append("  \"truncated\": ").append(edgeCount >= maxEdges || fnCount >= maxFns ? "true" : "false").append("\n");
        sb.append("}\n");

        try (BufferedWriter w = new BufferedWriter(new FileWriter(out, StandardCharsets.UTF_8))) {
            w.write(sb.toString());
        }

        // Optional Graphviz (no extra deps). Full edge list stays in JSON.
        try {
            File dot = new File(out.getAbsolutePath().replace(".json", ".dot"));
            if (dot.getAbsolutePath().equals(out.getAbsolutePath())) {
                dot = new File(out.getAbsolutePath() + ".dot");
            }
            try (BufferedWriter w = new BufferedWriter(new FileWriter(dot, StandardCharsets.UTF_8))) {
                w.write("digraph CallGraph {\n");
                w.write("  // ScooterCheck Phase-2; edges=" + edgeCount
                    + " unresolved=" + unresolved + " heuristic=" + heuristic + "\n");
                w.write("  // Full edges: sibling .json (static | heuristic | unresolved)\n");
                w.write("  label=\"callgraph edges=" + edgeCount + "\";\n");
                w.write("}\n");
            }
        } catch (Exception ignored) {
        }

        println("ExportCallGraph: " + edgeCount + " edges -> " + out.getAbsolutePath());
    }

    private static void appendEdge(
        StringBuilder sb,
        String fromAddr,
        String fromName,
        String toAddr,
        String toName,
        String kind,
        String evidence
    ) {
        sb.append("    {");
        sb.append("\"from\": ").append(jq(fromAddr)).append(", ");
        sb.append("\"fromName\": ").append(jq(fromName)).append(", ");
        sb.append("\"to\": ").append(toAddr == null ? "null" : jq(toAddr)).append(", ");
        sb.append("\"toName\": ").append(toName == null ? "null" : jq(toName)).append(", ");
        sb.append("\"kind\": ").append(jq(kind)).append(", ");
        sb.append("\"evidence\": ").append(jq(evidence));
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
