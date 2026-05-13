"""One-shot migration: add/correct group_title field on every requirement in the TOML.

Titles recovered from git diff (headers removed from paraphrase in recent commits)
plus inferred titles for requirements that never had an explicit header.
"""

from pathlib import Path
import tomlkit

TOML_PATH = Path(__file__).parent.parent / "verification_plan" / "verification_plan.toml"

TITLES: dict[str, str] = {
    # LLC
    "REQ-001": "LLC notification and timestamping",
    "REQ-002": "LLC transmission request and abort timing",
    "REQ-003": "Retransmission policy",
    "REQ-004": "Frame acceptance filtering",
    "REQ-005": "LLC transfer status reporting",
    "REQ-036": "DLC byte-count mapping",
    # MAC
    "REQ-006": "CRC rules",
    "REQ-007": "Error and overload flags",
    "REQ-008": "Inter-frame space",
    "REQ-010": "Frame initiation",
    "REQ-011": "Remote frame",
    "REQ-012": "SRR and RRS reserved bits",
    "REQ-013": "CRC bit stream coverage",
    "REQ-014": "Frame acknowledgement",
    "REQ-015": "FDF bit and CC/FD format differentiation",
    "REQ-016": "ESI bit transmission",
    "REQ-017": "Stuff count (SBC) field",
    "REQ-018": "CRC delimiter",
    "REQ-019": "Bit stuffing",
    "REQ-020": "End of frame (EOF)",
    "REQ-022": "MAC error detection",
    "REQ-023": "Error flag initiation and FCRC error behaviour",
    "REQ-024": "Overload frame",
    "REQ-035": "BRS bit rate switching",
    "REQ-037": "Bit transmission order",
    "REQ-039": "MAC data consistency",
    "REQ-040": "Error signalling enable",
    # PCS
    "REQ-025": "PCS bit timing configuration",
    "REQ-026": "Propagation segment sizing",
    "REQ-027": "Transmitter delay compensation",
    "REQ-028": "PCS synchronisation",
    "REQ-029": "Oscillator frequency tolerance",
    # system
    "REQ-009": "Bus re-integration",
    "REQ-021": "Bus arbitration",
    "REQ-030": "PCS bus-off isolation and signalling",
    "REQ-038": "Node start-up",
    # FCE
    "REQ-031": "FCE reset and response",
    "REQ-032": "Error counter rules (REC and TEC)",
    "REQ-033": "Prolonged dominant sequence",
    "REQ-034": "Error confinement state transitions",
}

with open(TOML_PATH) as f:
    doc = tomlkit.load(f)

reqs = doc["requirement"]
for req in reqs:
    rid = req.get("id", "")
    req["group_title"] = TITLES.get(rid, "")

    # REQ-032: remove the embedded header from the paraphrase
    if rid == "REQ-032":
        p = req.get("paraphrase", "")
        first_line = p.split("\n")[0].strip()
        if first_line == "Error counter rules (REC and TEC):":
            req["paraphrase"] = "\n".join(p.split("\n")[1:]).lstrip("\n")

with open(TOML_PATH, "w") as f:
    tomlkit.dump(doc, f)

print(f"Done. Set group_title on {len(reqs)} requirements.")
missing = [r["id"] for r in reqs if not r.get("group_title")]
if missing:
    print(f"Still empty: {missing}")
else:
    print("All requirements have a group_title.")
