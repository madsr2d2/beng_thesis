import re
import tomlkit
import json


def format_value(value):
    """Format a Python value as TOML."""
    if isinstance(value, bool):
        return "true" if value else "false"
    elif isinstance(value, str):
        return json.dumps(value)
    elif isinstance(value, (list, dict)):
        return json.dumps(value)
    else:
        return str(value)


def migrate_vplan(input_file: str, output_file: str):
    print(f"Reading old format from {input_file}...")

    # 1. Read the old TOML file
    with open(input_file, "r", encoding="utf-8") as f:
        old_doc = tomlkit.load(f)

    # 2. Create a fresh TOML document for the new format
    new_doc = tomlkit.document()
    new_doc.add(
        tomlkit.comment("============================================================")
    )
    new_doc.add(tomlkit.comment(" CAN SYSTEM VERIFICATION PLAN (MIGRATED)"))
    new_doc.add(
        tomlkit.comment("============================================================")
    )

    # Regex to split ID like 'FRM001TX' into ('FRM', '001', 'TX')
    # Group 1: 3 letters, Group 2: 3 digits, Group 3: 0 or more letters
    id_pattern = re.compile(r"^([A-Z]{3})(\d{3})([A-Z]*)$")

    old_reqs = old_doc.get("requirements", {})

    # First pass: collect and validate all requirements
    valid_reqs = []
    new_reqs = {}
    for old_id, data in old_reqs.items():
        # Clean up the ID in case there are weird hidden characters
        clean_id = old_id.strip()

        # Parse the old ID
        match = id_pattern.match(clean_id)
        if not match:
            print(
                f"Warning: ID '{clean_id}' does not match standard format. Skipping or needs manual fix."
            )
            continue

        category, _, side = match.groups()

        # Normalize status to lowercase
        old_status = data.get("status", "unverified").lower()

        # Create the new entry dict to store all fields
        entry = {
            "category": category,
            "side": side if side else "BOTH",
            "format": data.get("format", []),
            "priority": data.get("priority", "medium"),
            "description": data.get("description", ""),
            "iso_reference": data.get("iso_reference", ""),
            "acceptance_criteria": data.get("acceptance_criteria", ""),
            "notes": data.get("notes", ""),
            "target_module": "",
            "verification": data.get("verification", ""),
            "verification_method": ["simulation", "formal"],
            "status": old_status,
            "simulation": {
                "test_case": data.get("tests", ""),
                "file": "",
                "passed": old_status == "verified",
                "coverage": "100%" if old_status == "verified" else "0%",
            },
            "formal": {
                "property_label": "",
                "file": "",
                "depth_reached": 0,
            },
        }

        # Collect valid entries (original_id, entry)
        valid_reqs.append((clean_id, entry))

    # Second pass: sort by original ID and assign sequential numeric keys
    valid_reqs.sort(key=lambda x: x[0])
    for seq_num, (_, entry) in enumerate(valid_reqs, start=1):
        numeric_key = f"{seq_num:03d}"
        new_reqs[numeric_key] = entry

    # 3. Write out the newly structured TOML with manual formatting for indentation
    with open(output_file, "w", encoding="utf-8") as f:
        # Write header with documentation
        f.write("# ISO reference: ISO 11898-1:2015\n")
        f.write("#\n")
        f.write("# Categories:\n")
        f.write(
            "#   FRM: Frame structure, fields, arbitration, control, stuffing, completion\n"
        )
        f.write("#   ERR: Error detection & handling (bit, stuff, form, CRC errors)\n")
        f.write("#   TMG: Bit timing, sample points, TDC compensation\n")
        f.write("#   CRC: CRC polynomial selection and generation\n")
        f.write("#\n")
        f.write("# Side:     TX = Transmitter\n")
        f.write("#\n")
        f.write("# Format:   CB = Classic Basic       CE = Classic Extended\n")
        f.write("#           FB = FD Basic            FE = FD Extended\n")
        f.write("#\n")
        f.write("# ============================================================\n\n")

        # Write each requirement with indented fields
        for req_id, entry in new_reqs.items():
            f.write(f"[requirements.{req_id}]\n")

            # Classification Metadata section
            f.write("# Classification Metadata\n")
            f.write(f"  category = {format_value(entry['category'])}\n")
            f.write(f"  side = {format_value(entry['side'])}\n")
            f.write(f"  format = {format_value(entry['format'])}\n")
            f.write(f"  priority = {format_value(entry['priority'])}\n")

            # Core Specification section
            f.write("# Core Specification\n")
            f.write(f"  description = {format_value(entry['description'])}\n")
            f.write(f"  iso_reference = {format_value(entry['iso_reference'])}\n")
            f.write(
                f"  acceptance_criteria = {format_value(entry['acceptance_criteria'])}\n"
            )
            f.write(f"  notes = {format_value(entry['notes'])}\n")
            f.write(f"  target_module = {format_value(entry['target_module'])}\n")

            # Verification Strategy & Status section
            f.write("# Verification Strategy & Status\n")
            f.write(f"  verification = {format_value(entry['verification'])}\n")
            f.write(
                f"  verification_method = {format_value(entry['verification_method'])}\n"
            )
            f.write(f"  status = {format_value(entry['status'])}\n")

            # Simulation subsection
            f.write(f"\n[requirements.{req_id}.simulation]\n")
            sim = entry["simulation"]
            f.write(f"  test_case = {format_value(sim['test_case'])}\n")
            f.write(f"  file = {format_value(sim['file'])}\n")
            f.write(f"  passed = {format_value(sim['passed'])}\n")
            f.write(f"  coverage = {format_value(sim['coverage'])}\n")

            # Formal subsection
            f.write(f"\n[requirements.{req_id}.formal]\n")
            formal = entry["formal"]
            f.write(f"  property_label = {format_value(formal['property_label'])}\n")
            f.write(f"  file = {format_value(formal['file'])}\n")
            f.write(f"  depth_reached = {format_value(formal['depth_reached'])}\n")

            f.write("\n")

    print(f"Successfully migrated {len(new_reqs)} requirements to {output_file}!")


if __name__ == "__main__":
    # Ensure you have your old file named 'old_plan.toml' in the same folder
    migrate_vplan("old_plan.toml", "requirements.toml")
