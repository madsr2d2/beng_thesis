import re
import tomlkit


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

    new_reqs = tomlkit.table()

    # Regex to split ID like 'FRM001TX' into ('FRM', '001', 'TX')
    # Group 1: 3 letters, Group 2: 3 digits, Group 3: 0 or more letters
    id_pattern = re.compile(r"^([A-Z]{3})(\d{3})([A-Z]*)$")

    old_reqs = old_doc.get("requirements", {})

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

        category, numeric_id, side = match.groups()

        # Create the new entry table
        entry = tomlkit.table()

        # --- Classification Metadata ---
        entry.add("category", category)
        entry.add("side", side if side else "BOTH")
        entry.add("format", data.get("format", []))
        entry.add(
            "priority", data.get("priority", "medium")
        )  # Default to medium if empty

        # --- Core Specification ---
        entry.add("description", data.get("description", ""))
        entry.add("iso_reference", data.get("iso_reference", ""))
        entry.add("acceptance_criteria", data.get("acceptance_criteria", ""))
        if "dependencies" in data:
            entry.add("dependencies", data.get("dependencies"))
        entry.add("notes", data.get("notes", ""))
        entry.add("target_module", "")  # New field, leave blank for now

        # --- Verification Strategy & Status ---
        entry.add("verification", data.get("verification", ""))
        entry.add("verification_method", ["simulation", "formal"])

        # Normalize status to lowercase
        old_status = data.get("status", "unverified").lower()
        entry.add("status", old_status)

        # --- Simulation Run Metrics ---
        sim_table = tomlkit.table()
        # Move the old "tests" string into the simulation test_case field
        sim_table.add("test_case", data.get("tests", ""))
        sim_table.add("file", "")
        # If it was already verified, assume it passed
        sim_table.add("passed", old_status == "verified")
        sim_table.add("coverage", "100%" if old_status == "verified" else "0%")
        entry.add("simulation", sim_table)

        # --- Formal Run Metrics ---
        formal_table = tomlkit.table()
        formal_table.add("property_label", "")
        formal_table.add("file", "")
        formal_table.add("depth_reached", 0)
        entry.add("formal", formal_table)

        # Add this entry to our new requirements table using the strict numeric ID
        new_reqs.add(numeric_id, entry)

    # Add the populated requirements table to the root document
    new_doc.add("requirements", new_reqs)

    # 3. Write out the newly structured TOML
    with open(output_file, "w", encoding="utf-8") as f:
        tomlkit.dump(new_doc, f)

    print(f"Successfully migrated {len(new_reqs)} requirements to {output_file}!")


if __name__ == "__main__":
    # Ensure you have your old file named 'old_plan.toml' in the same folder
    migrate_vplan("old_plan.toml", "requirements.toml")
