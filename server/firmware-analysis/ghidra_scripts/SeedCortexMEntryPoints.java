// Auto-seed Cortex-M vector-table entry points + follow Thumb callees (Phase 2.2B).
// Usage: -preScript SeedCortexMEntryPoints.java
// Optional args: [maxVectors] [baseOverrideHex] [maxCallDepth]
//@category ScooterCheck

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.lang.Register;
import ghidra.program.model.listing.Function;
import ghidra.program.model.listing.Instruction;
import ghidra.program.model.mem.Memory;
import ghidra.program.model.mem.MemoryAccessException;
import ghidra.program.model.symbol.FlowType;
import ghidra.program.model.symbol.RefType;
import ghidra.program.model.symbol.Reference;
import ghidra.program.model.symbol.SourceType;

import java.math.BigInteger;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Queue;
import java.util.Set;

/**
 * Reads the Cortex-M IVT at the program image base, creates Thumb functions for
 * plausible handlers, then recursively follows call flows within the image.
 * Does not require a manual address list. Uncertain IVT layouts are logged.
 */
public class SeedCortexMEntryPoints extends GhidraScript {

    private static final String[] VECTOR_NAMES = {
        "initialSP", "reset_handler", "NMI_Handler", "HardFault_Handler",
        "MemManage_Handler", "BusFault_Handler", "UsageFault_Handler",
        "reserved7", "reserved8", "reserved9", "reserved10",
        "SVC_Handler", "DebugMon_Handler", "reserved13", "PendSV_Handler", "SysTick_Handler"
    };

    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        int maxVectors = 48;
        int maxCallDepth = 32;
        Address base = currentProgram.getImageBase();
        if (args != null && args.length >= 1 && args[0] != null && !args[0].isEmpty()) {
            try {
                maxVectors = Math.max(8, Integer.parseInt(args[0].trim()));
            } catch (NumberFormatException ignored) {
            }
        }
        if (args != null && args.length >= 2 && args[1] != null && !args[1].isEmpty()) {
            try {
                long override = Long.parseLong(args[1].trim().toLowerCase().replace("0x", ""), 16);
                base = toAddr(override);
            } catch (Exception ignored) {
            }
        }
        if (args != null && args.length >= 3 && args[2] != null && !args[2].isEmpty()) {
            try {
                maxCallDepth = Math.max(1, Integer.parseInt(args[2].trim()));
            } catch (NumberFormatException ignored) {
            }
        }

        Memory mem = currentProgram.getMemory();
        List<String> notes = new ArrayList<>();
        List<Address> seeds = new ArrayList<>();
        int created = 0;
        int skipped = 0;
        boolean spOk = false;
        boolean resetOk = false;

        // BinaryLoader may map the block at loader-baseAddr while ImageBase stays 0.
        // Prefer the first initialized block that looks like flash / contains the IVT.
        Address resolvedBase = resolveIvtBase(base, mem, notes);
        base = resolvedBase;

        long imageSize = Math.max(mem.getSize(), 1);
        // Tiny synthetic / overlapping images: only trust Reset; discover the rest via
        // call-following + literal Thumb pointers (avoid treating code words as IRQ vectors).
        boolean compactImage = imageSize < 0x400;
        int vectorLimit = compactImage ? 2 : maxVectors;
        notes.add("imageSize=" + imageSize + (compactImage ? ":compact" : ":full"));

        for (int i = 0; i < vectorLimit; i++) {
            Address slot = base.add(i * 4L);
            int word;
            try {
                word = mem.getInt(slot);
            } catch (MemoryAccessException e) {
                notes.add("ivt_read_fail@" + slot);
                break;
            }
            long unsigned = word & 0xFFFFFFFFL;

            if (i == 0) {
                spOk = looksLikeSram(unsigned);
                notes.add("sp=" + String.format("0x%08x", unsigned) + (spOk ? ":ok" : ":weak"));
                continue;
            }

            boolean thumb = (unsigned & 1L) == 1L;
            long dest = unsigned & ~1L;
            if (!thumb) {
                skipped++;
                continue;
            }
            if (!looksLikeCode(dest, base)) {
                skipped++;
                continue;
            }

            Address entry = toAddr(dest);
            String name = i < VECTOR_NAMES.length ? VECTOR_NAMES[i] : ("IRQ_Handler_" + (i - 16));
            // High-confidence exception vectors only (skip reserved slots).
            boolean highConfidence = (i == 1)
                || (!compactImage && i >= 2 && i <= 15
                    && i != 7 && i != 8 && i != 9 && i != 10 && i != 13);
            if (i == 1) {
                name = "reset_handler";
                resetOk = true;
            } else if (!highConfidence) {
                skipped++;
                notes.add("skipWeakIvt@" + i);
                continue;
            }

            if (ensureThumbFunction(entry, name)) {
                created++;
                seeds.add(entry);
            } else {
                skipped++;
            }
        }

        int fromCalls = expandFromSeeds(seeds, maxCallDepth);
        created += fromCalls;

        int fromLiterals = seedLiteralThumbPointers(base, notes);
        created += fromLiterals;

        println("SeedCortexMEntryPoints: base=" + base
            + " created=" + created
            + " fromCalls=" + fromCalls
            + " fromLiterals=" + fromLiterals
            + " skipped=" + skipped
            + " spOk=" + spOk
            + " resetOk=" + resetOk
            + " notes=" + String.join(",", notes));
        if (!spOk || !resetOk) {
            printerr("SeedCortexMEntryPoints: IVT only partially plausible — architecture/base may be uncertain.");
        }
    }

    /**
     * Scan aligned words for Thumb code pointers into this image (literal pools /
     * vector-like constants). Candidates require a plausible Thumb prologue/epilogue
     * halfword; they are labeled FUN_* (uncertain until analysis confirms).
     */
    private int seedLiteralThumbPointers(Address base, List<String> notes) {
        Memory mem = currentProgram.getMemory();
        long baseOff = base.getOffset();
        long size = Math.max(currentProgram.getMemory().getSize(), 1);
        long end = baseOff + size;
        int created = 0;
        int scanned = 0;
        for (long off = 0; off + 4 <= size; off += 4) {
            Address slot = base.add(off);
            int word;
            try {
                word = mem.getInt(slot);
            } catch (MemoryAccessException e) {
                break;
            }
            long unsigned = word & 0xFFFFFFFFL;
            if ((unsigned & 1L) == 0L) {
                continue;
            }
            long dest = unsigned & ~1L;
            if (dest < baseOff || dest >= end) {
                continue;
            }
            if (getFunctionAt(toAddr(dest)) != null) {
                continue;
            }
            if (!looksLikeThumbPrologue(dest, base)) {
                continue;
            }
            scanned++;
            Address entry = toAddr(dest);
            String name = "FUN_" + String.format("%08x", dest);
            if (ensureThumbFunction(entry, name)) {
                created++;
                notes.add("literalThumb@" + entry);
            }
        }
        notes.add("literalScan=" + scanned);
        return created;
    }

    private boolean looksLikeThumbPrologue(long dest, Address base) {
        try {
            Address a = toAddr(dest);
            int half = currentProgram.getMemory().getShort(a) & 0xFFFF;
            // Common Thumb-1 / Thumb-2 function starts seen on Cortex-M:
            // push {..,lr} 0xb5xx, sub sp 0xb08x, bx lr 0x4770, movs/adds early ops
            if ((half & 0xFF00) == 0xB500) {
                return true; // push with lr
            }
            if ((half & 0xFF00) == 0xB000) {
                return true; // add/sub sp
            }
            if (half == 0x4770) {
                return true; // bx lr (leaf)
            }
            if ((half & 0xFFC0) == 0x1840) {
                return true; // adds rd, rn, rm family (tiny leaves)
            }
            if ((half & 0xFFC0) == 0x4340) {
                return true; // muls
            }
            if ((half & 0xFF00) == 0x2000) {
                return true; // movs rd, #imm then call sites
            }
            // Reject obvious ASCII / padding
            if (half == 0xFFFF || half == 0x0000) {
                return false;
            }
            return false;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean ensureThumbFunction(Address entry, String name) {
        try {
            setThumbContext(entry);
            disassemble(entry);
        } catch (Exception ignored) {
        }
        Function fn = getFunctionAt(entry);
        if (fn == null) {
            try {
                fn = createFunction(entry, name);
            } catch (Exception e) {
                return false;
            }
        }
        if (fn == null) {
            return false;
        }
        try {
            if (name != null && !name.isEmpty() && !name.equals(fn.getName())) {
                fn.setName(name, SourceType.ANALYSIS);
            }
        } catch (Exception ignored) {
        }
        return true;
    }

    private void setThumbContext(Address entry) {
        try {
            Register tMode = currentProgram.getProgramContext().getRegister("TMode");
            if (tMode != null) {
                currentProgram.getProgramContext().setValue(tMode, entry, entry, BigInteger.ONE);
            }
        } catch (Exception ignored) {
        }
    }

    private int expandFromSeeds(List<Address> seeds, int maxDepth) {
        Queue<Address> queue = new ArrayDeque<>(seeds);
        Set<Long> visited = new HashSet<>();
        for (Address a : seeds) {
            visited.add(a.getOffset());
        }
        int created = 0;
        int depthGuard = 0;
        int maxSteps = Math.max(64, maxDepth * 64);

        while (!queue.isEmpty() && depthGuard++ < maxSteps) {
            Address cur = queue.poll();
            try {
                setThumbContext(cur);
                disassemble(cur);
            } catch (Exception ignored) {
            }

            Instruction insn = getInstructionAt(cur);
            int walked = 0;
            while (insn != null && walked++ < 256) {
                FlowType ft = insn.getFlowType();
                // Follow calls only — jumps are typically intra-function and create FPs.
                if (ft != null && ft.isCall()) {
                    Address[] flows = insn.getFlows();
                    if (flows != null) {
                        for (Address target : flows) {
                            created += maybeSeedCallee(target, visited, queue);
                        }
                    }
                }
                Reference[] refs = insn.getReferencesFrom();
                if (refs != null) {
                    for (Reference ref : refs) {
                        if (ref == null) {
                            continue;
                        }
                        RefType rt = ref.getReferenceType();
                        if (rt == null || !rt.isCall()) {
                            continue;
                        }
                        created += maybeSeedCallee(ref.getToAddress(), visited, queue);
                    }
                }
                if (ft != null && ft.isTerminal()) {
                    break;
                }
                insn = insn.getNext();
            }
        }
        return created;
    }

    private int maybeSeedCallee(Address target, Set<Long> visited, Queue<Address> queue) {
        if (target == null) {
            return 0;
        }
        long off = target.getOffset() & ~1L;
        Address thumbTarget = toAddr(off);
        if (!looksLikeCode(off, currentProgram.getMinAddress())) {
            return 0;
        }
        Function existing = getFunctionContaining(thumbTarget);
        if (existing != null && existing.getEntryPoint() != null
            && existing.getEntryPoint().getOffset() != off) {
            return 0;
        }
        if (!visited.add(off)) {
            return 0;
        }
        if (getFunctionAt(thumbTarget) == null
            && !looksLikeThumbPrologue(off, currentProgram.getMinAddress())) {
            return 0;
        }
        String autoName = "FUN_" + String.format("%08x", off);
        if (ensureThumbFunction(thumbTarget, autoName)) {
            queue.add(thumbTarget);
            return 1;
        }
        return 0;
    }

    private Address resolveIvtBase(Address imageBase, Memory mem, List<String> notes) {
        // 1) Explicit override already applied via args → imageBase may still be wrong; try blocks.
        ghidra.program.model.mem.MemoryBlock[] blocks = mem.getBlocks();
        Address best = null;
        boolean bestLikely = false;
        for (ghidra.program.model.mem.MemoryBlock block : blocks) {
            if (block == null || !block.isInitialized()) {
                continue;
            }
            Address start = block.getStart();
            try {
                int sp = mem.getInt(start);
                int reset = mem.getInt(start.add(4));
                long spU = sp & 0xFFFFFFFFL;
                long resetU = reset & 0xFFFFFFFFL;
                boolean ok = looksLikeSram(spU) && ((resetU & 1L) == 1L);
                notes.add("block@" + start + (ok ? ":ivt-ok" : ":ivt-weak"));
                if (ok) {
                    return start;
                }
                if (best == null) {
                    best = start;
                }
            } catch (MemoryAccessException e) {
                notes.add("block_read_fail@" + start);
            }
        }
        // 2) Prefer common Cortex-M flash base if a block exists there
        try {
            Address flash = toAddr(0x08000000L);
            if (mem.getBlock(flash) != null) {
                notes.add("preferFlashBase=0x08000000");
                return flash;
            }
        } catch (Exception ignored) {
        }
        if (best != null) {
            notes.add("fallbackBlockBase=" + best);
            return best;
        }
        notes.add("fallbackImageBase=" + imageBase);
        return imageBase;
    }

    private static boolean looksLikeSram(long v) {
        return (v >= 0x20000000L && v < 0x20100000L)
            || (v >= 0x10000000L && v < 0x10080000L);
    }

    private boolean looksLikeCode(long dest, Address imageBase) {
        long base = imageBase.getOffset();
        long end = base + Math.max(currentProgram.getMemory().getSize(), 1);
        if (dest >= base && dest < end) {
            return true;
        }
        if (dest >= 0x08000000L && dest < 0x08200000L) {
            return true;
        }
        if (dest >= 0x00000000L && dest < 0x00200000L) {
            return true;
        }
        return false;
    }
}
