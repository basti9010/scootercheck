/*
  ScooterCheck — CFW / unlock heuristics on decrypted VCU/MCU images.
  Hits are investigative signals, not proof of installation.
*/

rule Ninebot_Packed_OpenCap_99 {
  meta:
    description = "Packed open-cap 0x6300 (≈99 km/h) present"
    confidence = "medium"
    family = "speed-imm"
  strings:
    $p99 = { 00 63 }
  condition:
    $p99
}

rule Ninebot_Packed_OpenCap_35_40_45 {
  meta:
    description = "Multiple open-cap packed speeds (35/40/45)"
    confidence = "medium"
    family = "speed-imm"
  strings:
    $p35 = { 00 23 }
    $p40 = { 00 28 }
    $p45 = { 00 2D }
  condition:
    2 of ($p35, $p40, $p45)
}

rule Ninebot_Legal_And_Open_Together {
  meta:
    description = "Legal cap (20/22) together with high open cap (50/99)"
    confidence = "high"
    family = "soft-unlock"
  strings:
    $legal20 = { 00 14 }
    $legal22 = { 00 16 }
    $open50 = { 00 32 }
    $open99 = { 00 63 }
  condition:
    (1 of ($legal20, $legal22)) and (1 of ($open50, $open99))
}

rule CFW_Ascii_Panic_Or_Unlock {
  meta:
    description = "ASCII hints often seen in custom/panic tooling artifacts"
    confidence = "low"
    family = "cfw-string"
  strings:
    $a1 = "panic" ascii nocase
    $a2 = "softunlock" ascii nocase
    $a3 = "soft_unlock" ascii nocase
    $a4 = "speedlimit" ascii nocase
    $a5 = "unlock" ascii nocase
  condition:
    1 of them
}

rule CFW_PanicSystem_Artifact {
  meta:
    description = "PanicSystem / panicsystem naming in image or leftover paths"
    confidence = "high"
    family = "panicsystem"
  strings:
    $p1 = "panicsystem" ascii nocase
    $p2 = "PanicSystem" ascii
    $p3 = "PANICSYSTEM" ascii
    $p4 = "panic_system" ascii nocase
  condition:
    1 of them
}

rule CFW_ScooterHacking_Artifact {
  meta:
    description = "ScooterHacking / SHFW / scooterhacking.org style markers"
    confidence = "high"
    family = "scooterhacking"
  strings:
    $s1 = "scooterhacking" ascii nocase
    $s2 = "ScooterHacking" ascii
    $s3 = "SHFW" ascii
    $s4 = "shfw" ascii
    $s5 = "scooterhacking.org" ascii nocase
  condition:
    1 of them
}

rule CFW_ESC_Custom_Strings {
  meta:
    description = "Common ESC/CFW patcher strings (ninebottea leftover / custom ESC)"
    confidence = "medium"
    family = "esc-cfw"
  strings:
    $e1 = "ESCFW" ascii
    $e2 = "escfw" ascii nocase
    $e3 = "customfw" ascii nocase
    $e4 = "cfw_version" ascii nocase
    $e5 = "MODDED" ascii
    $e6 = "NB_CFW" ascii
  condition:
    1 of them
}

rule CFW_Wide_Open_Caps_Cluster {
  meta:
    description = "Dense cluster of high open caps (40/45/50/99) — typical CFW image"
    confidence = "high"
    family = "speed-imm"
  strings:
    $p40 = { 00 28 }
    $p45 = { 00 2D }
    $p50 = { 00 32 }
    $p99 = { 00 63 }
  condition:
    3 of them
}

rule CFW_Region_Bypass_Hints {
  meta:
    description = "Region / StVZO bypass wording in plaintext firmware"
    confidence = "medium"
    family = "region"
  strings:
    $r1 = "stvzo" ascii nocase
    $r2 = "no_limit" ascii nocase
    $r3 = "nolimit" ascii nocase
    $r4 = "region_lock" ascii nocase
    $r5 = "regionlock" ascii nocase
    $r6 = "geo_fence" ascii nocase
  condition:
    1 of them
}

rule CFW_NinebotTea_Leftover {
  meta:
    description = "ninebottea / NBTEA tooling leftover strings"
    confidence = "medium"
    family = "tooling"
  strings:
    $t1 = "ninebottea" ascii nocase
    $t2 = "NBTEA" ascii
    $t3 = "nbtea" ascii
  condition:
    1 of them
}
