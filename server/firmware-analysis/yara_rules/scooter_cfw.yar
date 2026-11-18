/*
  ScooterCheck — lightweight CFW / unlock heuristics on decrypted VCU/MCU images.
  Hits are investigative signals, not proof of installation.
*/

rule Ninebot_Packed_OpenCap_99 {
  meta:
    description = "Packed open-cap 0x6300 (≈99 km/h) present"
    confidence = "medium"
  strings:
    $p99 = { 00 63 }
  condition:
    $p99
}

rule Ninebot_Packed_OpenCap_35_40_45 {
  meta:
    description = "Multiple open-cap packed speeds (35/40/45)"
    confidence = "medium"
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
  strings:
    $a1 = "panic" ascii nocase
    $a2 = "softunlock" ascii nocase
    $a3 = "soft_unlock" ascii nocase
    $a4 = "speedlimit" ascii nocase
    $a5 = "unlock" ascii nocase
  condition:
    1 of them
}
