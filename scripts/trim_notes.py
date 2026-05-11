"""Trim notes fields in verification_plan.toml to only residual ambiguity."""
import re

PLAN_PATH = "/home/madsr2d2/beng_thesis/verification_plan/verification_plan.toml"

TRIMMED_NOTES = {
    # Empty: paraphrase + label + file + verification_method are fully sufficient.
    "REQ-001": "",
    "REQ-006": "",
    "REQ-009": "",
    "REQ-010": "",
    "REQ-011": "",
    "REQ-013": "",
    "REQ-014": "",
    "REQ-016": "",
    "REQ-017": "",
    "REQ-019": "",
    "REQ-020": "",
    "REQ-025": "",
    "REQ-026": "",
    "REQ-028": "",
    "REQ-031": "",
    "REQ-032": "",
    "REQ-035": "",
    "REQ-036": "",
    "REQ-037": "",
    "REQ-040": "",

    # Scope carve-outs and non-obvious architectural details.
    "REQ-002": (
        "The timing bound ('second SOF') is bus-activity-dependent, not a fixed cycle count."
    ),
    "REQ-003": (
        "The two-SOF and three-SOF deadlines govern the LLC-to-MAC handoff, "
        "not MAC transmission duration."
    ),
    "REQ-004": (
        "Retransmission limit configures from 0 (no retransmission) to at least 6, "
        "with optional unlimited."
    ),
    "REQ-005": (
        "P3 recommendation ('should'). "
        "Filter must be a single self-contained operation with no carry-over state "
        "from previous frame transactions."
    ),
    "REQ-008": (
        "Code inspection targets the FSM delimiter counter start condition; "
        "waveform inspection targets the resulting bit sequence in GTKWave."
    ),
    "REQ-012": (
        "Protocol exception event (third trigger in paragraph 6.6.7.5) is not implemented."
    ),
    "REQ-015": (
        "SRR applies to CE and FE only; RRS applies to FB and FE only. "
        "The RX sub-claim is implicit: no form error is generated because "
        "the FSM has no polarity check at those bit positions."
    ),
    "REQ-018": (
        "Protocol exception handling is not implemented; "
        "a recessive res bit always produces a form error."
    ),
    "REQ-021": (
        "The second-recessive-bit tolerance is provided by the 2-bit FD ACK window in s_ack, "
        "not by waiting an extra bit in s_crc_delimiter."
    ),
    "REQ-027": (
        "The consecutive-bit counter must not run in the fixed-stuffing CRC region of FD frames."
    ),
    "REQ-029": (
        "For FD frames the SBC comparison and SBC parity check are separate sub-claims "
        "from the FCRC comparison."
    ),
    "REQ-030": "PCRC error (XL-only) is out of scope.",
    "REQ-033": "XL data bit rate (third configuration set) is out of scope.",
    "REQ-038": (
        "Two PCS instances run with a clock offset at the maximum ISO 7.3.6 tolerance "
        "(df = 0.2% from Eq. 3, SJW=4, N=100), alternating TX/RX roles each frame. "
        "XL data rate conditions (Eq. 8) are out of scope."
    ),
    "REQ-039": (
        "The FCE-side idle condition counting and bus-off state transition are covered by REQ-045."
    ),
    "REQ-041": (
        "The reset must take effect within one clock cycle of the request asserting."
    ),
    "REQ-042": (
        "Counter values are inferred from error_active/error_passive threshold crossings; "
        "the raw TEC and REC values are internal. "
        "Rule h requires the '>127 set to 119-127' clamp path to be confirmed, "
        "not just the +1 and -1 paths."
    ),
    "REQ-043": (
        "Exception 2 is architecturally handled by the MAC routing c_lost_arb for a recessive "
        "stuff bit monitored as dominant during arbitration; "
        "no FCE-side exception logic exists for this case."
    ),
    "REQ-044": (
        "Sub-layer split: the MAC counts consecutive dominant bits and signals "
        "error_delimiter_too_late; the FCE is only responsible for the counter increments. "
        "The MAC-side threshold logic (14-bit for active/overload flag, 8-bit for passive flag) "
        "is verified by MAC testbenches."
    ),
    "REQ-045": (
        "test_bus_off covers sub-claims 1, 3, and 4; "
        "test_bus_off_recovery covers sub-claims 2 and 5."
    ),

    # Coverage closure criteria.
    "REQ-007": (
        "Coverage closure criterion: three bins - "
        "(1) CB or CE frame (CRC_15), "
        "(2) FB or FE frame with DLC <= 8 (CRC_17), "
        "(3) FB or FE frame with DLC > 8 (CRC_21) - must each be hit."
    ),
    "REQ-022": (
        "Coverage closure criterion: four bins - "
        "(1) CB frame with a stuff bit inserted, "
        "(2) CE frame with a stuff bit inserted, "
        "(3) FB frame with stuffing halting at the data/CRC boundary, "
        "(4) FE frame with the same - must each be hit."
    ),
    "REQ-023": (
        "The initial FSB is unconditional even when the preceding field does not end "
        "with five consecutive identical bits; if it does, only the FSB is emitted (no double-stuffing). "
        "Coverage closure criterion: four format-by-CRC-length bins - "
        "(1) FB with CRC_17, (2) FE with CRC_17, (3) FB with CRC_21, (4) FE with CRC_21 - "
        "plus at least one frame exercising the no-double-stuffing rule."
    ),
    "REQ-024": (
        "Coverage closure criterion: three bins - "
        "(1) successful TX closure across all four formats, "
        "(2) successful RX validation across all four formats, "
        "(3) dominant seventh EOF bit triggering an OF rather than a form error."
    ),
    "REQ-034": (
        "Coverage closure criterion: five delay-sweep bins - "
        "(transceiver_d=50 ns, bus_d=300 ns) down to (10 ns, 60 ns) - "
        "must each yield successful frame exchange."
    ),
}


def replace_notes(content: str, req_id: str, new_notes: str) -> str:
    # Split on [[requirement]] markers, keeping the marker
    parts = re.split(r'(?=\[\[requirement\]\])', content)

    result = []
    for part in parts:
        id_match = re.search(r'\bid = "([^"]+)"', part)
        if id_match and id_match.group(1) == req_id:
            # Replace the notes field on its line; greedy .* catches multi-word content
            new_part = re.sub(r'notes = ".*"', f'notes = "{new_notes}"', part)
            if new_part == part:
                print(f"  WARNING: no notes field matched for {req_id}")
            result.append(new_part)
        else:
            result.append(part)

    return "".join(result)


def main():
    with open(PLAN_PATH, "r") as f:
        content = f.read()

    for req_id, new_notes in TRIMMED_NOTES.items():
        print(f"Processing {req_id}...")
        content = replace_notes(content, req_id, new_notes)

    with open(PLAN_PATH, "w") as f:
        f.write(content)

    print(f"\nDone. Processed {len(TRIMMED_NOTES)} requirements.")


if __name__ == "__main__":
    main()
