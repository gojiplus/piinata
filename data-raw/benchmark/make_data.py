"""Synthetic survey with known answers: which columns hold personal data."""
import json, random, sys
from pathlib import Path
import pandas as pd

out = Path(sys.argv[1]); random.seed(7); n = 200
first = ["Sunita", "Ramesh", "Geeta", "Mohammad", "Lakshmi", "Arjun", "Pooja", "Imran", "Kavita", "Suresh"]
last = ["Devi", "Yadav", "Meena", "Khan", "Sharma", "Paswan", "Kumari", "Ansari", "Singh", "Gurjar"]
villages = ["Bhogadeet", "Ajgara", "Palpur", "Netrad", "Jharoli", "Biliya", "Konra", "Sewali"]
name = [f"{random.choice(first)} {random.choice(last)}" for _ in range(n)]
phone = [f"{random.choice('6789')}{random.randrange(10**8, 10**9)}" for _ in range(n)]
truth = {}
def col(key, values, pii, label):
    truth[key] = {"pii": pii, "label": label}; return values
d = pd.DataFrame({
    # personal data, named plainly
    "resp_name": col("resp_name", name, True, "Respondent name"),
    "hh_phone": col("hh_phone", [f"+91 {p[:5]} {p[5:]}" for p in phone], True, "Household phone"),
    "dob": col("dob", [f"{random.randint(1,28):02d}/{random.randint(1,12):02d}/{random.randint(1955,2000)}" for _ in range(n)], True, "Date of birth"),
    "village": col("village", [random.choice(villages) for _ in range(n)], True, "Village"),
    "gps_lat": col("gps_lat", [round(26 + random.random(), 6) for _ in range(n)], True, "GPS latitude"),
    "gps_lon": col("gps_lon", [round(75 + random.random(), 6) for _ in range(n)], True, "GPS longitude"),
    # personal data hidden behind question numbers: only the values give it away
    "q12": col("q12", [f"{a.split()[0].lower()}{random.randint(1,99)}@gmail.com" for a in name], True, "Q12"),
    "q13": col("q13", phone, True, "Q13"),
    "q14": col("q14", [f"{random.randrange(2000,9999)} {random.randrange(1000,9999)} {random.randrange(1000,9999)}" for _ in range(n)], True, "Q14"),
    "q15": col("q15", [random.choice(first) + " " + random.choice(last) for _ in range(n)], True, "Q15"),
    "q20_text": col("q20_text", [random.choice([
        f"Please call my husband {random.choice(first)} on {random.choice(phone)}", "No comment",
        f"I live near the temple in {random.choice(villages)}, house 14", "The road is bad", "Nothing to add"]) for _ in range(n)], True, "Any other comments"),
    "q21": col("q21", [f"{random.randint(1,300)}, Ward {random.randint(1,12)}, {random.choice(villages)}" for _ in range(n)], True, "Q21"),
    # not personal, but names that contain a scanner keyword
    "reason_visit": col("reason_visit", [random.choice(["work", "family", "health"]) for _ in range(n)], False, "Reason for visit"),
    "season": col("season", [random.choice(["kharif", "rabi"]) for _ in range(n)], False, "Crop season"),
    "relation_head": col("relation_head", [random.randint(1, 6) for _ in range(n)], False, "Relation to head (code)"),
    "latrine_type": col("latrine_type", [random.randint(1, 4) for _ in range(n)], False, "Type of latrine"),
    "long_term_plan": col("long_term_plan", [random.randint(1, 5) for _ in range(n)], False, "Has a long-term plan (1-5)"),
    "second_job": col("second_job", [random.randint(0, 1) for _ in range(n)], False, "Has a second job"),
    "minutes_walk": col("minutes_walk", [random.randint(1, 90) for _ in range(n)], False, "Minutes walk to water"),
    "household_size": col("household_size", [random.randint(1, 9) for _ in range(n)], False, "Household size"),
    "school_quality": col("school_quality", [random.randint(1, 5) for _ in range(n)], False, "School quality rating"),
    "social_trust": col("social_trust", [random.randint(1, 5) for _ in range(n)], False, "Social trust scale"),
    "blockage": col("blockage", [random.randint(0, 1) for _ in range(n)], False, "Drain blockage reported"),
    "personal_income": col("personal_income", [random.randrange(2000, 40000, 500) for _ in range(n)], False, "Monthly income"),
    # not personal, plain
    "consent": col("consent", [1] * n, False, "Consented"),
    "satisfaction": col("satisfaction", [random.randint(1, 5) for _ in range(n)], False, "Satisfaction 1-5"),
    "q30": col("q30", [random.choice(["Yes", "No", "Don't know"]) for _ in range(n)], False, "Q30"),
    "crop": col("crop", [random.choice(["wheat", "bajra", "mustard"]) for _ in range(n)], False, "Main crop"),
})
# Harder personal data: names in Devanagari or typed in lower case, and an
# Indian postal address with its PIN code.
deva_first = ["सुनीता", "रमेश", "गीता", "मोहम्मद", "लक्ष्मी", "अर्जुन", "पूजा", "इमरान"]
deva_last = ["देवी", "यादव", "मीणा", "खान", "शर्मा", "पासवान", "कुमारी", "अंसारी"]
tehsils = ["Todabhim", "Hindaun", "Nadoti", "Mandrayal", "Sapotra", "Bamanwas"]
districts = ["Karauli", "Sawai Madhopur", "Dausa", "Jhunjhunu", "Sri Ganganagar", "Pali"]
d["q16"] = col("q16", [f"{random.choice(deva_first)} {random.choice(deva_last)}" for _ in range(n)], True, "Q16")
d["q17"] = col("q17", [f"{random.choice(first)} {random.choice(last)}".lower() for _ in range(n)], True, "Q17")
d["q22"] = col("q22", [
    f"House {random.randint(1, 300)}, {random.choice(villages)}, Tehsil {random.choice(tehsils)}, "
    f"District {random.choice(districts)}, Rajasthan {random.randint(301001, 345034)}" for _ in range(n)], True, "Q22")
# Decoys: Indian place, facility, scheme, caste and crop names. They are
# capitalized, often several words, and many are distinct, so they look like
# person names; none identifies a person.
suffixes = ["Khurd", "Kalan", "Pura", "Nagar", "Ka Bas", "Gaon", "Dhani"]
places = sorted({f"{v} {sfx}" for v in villages + tehsils for sfx in suffixes})
facilities = ["Primary Health Centre", "Government Senior Secondary School", "Anganwadi Centre", "Gram Panchayat Bhawan", "Cooperative Society"]
d["q32"] = col("q32", [random.choice(places) for _ in range(n)], False, "Q32")
d["q33"] = col("q33", [f"{random.choice(facilities)} {random.choice(villages + tehsils)}" for _ in range(n)], False, "Q33")
d["q34"] = col("q34", [random.choice(["Pradhan Mantri Awas Yojana", "Mahatma Gandhi NREGA", "Ujjwala Yojana", "Jan Dhan Yojana", "Kisan Samman Nidhi"]) for _ in range(n)], False, "Q34")
d["q35"] = col("q35", [random.choice(["Meena", "Jatav", "Gurjar", "Mali", "Bairwa", "Brahmin", "Mahajan", "Saini"]) for _ in range(n)], False, "Q35")
d["q36"] = col("q36", [random.choice(["Pusa Basmati", "Raj Vijay", "Lok One", "Giriraj Bajra", "Pusa Bold", "Varuna Mustard"]) for _ in range(n)], False, "Q36")
d["district"] = col("district", [random.choice(districts) for _ in range(n)], False, "District")
# United States: names and street addresses, and decoys that look like them
# (cities, businesses, street names on their own).
us_first = ["James", "Mary", "Robert", "Patricia", "Michael", "Jennifer", "David", "Linda", "Maria", "Jose"]
us_last = ["Smith", "Johnson", "Williams", "Brown", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Lee"]
streets = ["Main St", "Oak Ave", "Maple Dr", "Washington Blvd", "Park Rd", "Elm St", "Cedar Ln", "Lake Shore Dr"]
cities = [("Springfield", "IL", "627"), ("Columbus", "OH", "432"), ("Austin", "TX", "787"), ("Fresno", "CA", "937"), ("Albany", "NY", "122")]
def us_address():
    city, state, zip3 = random.choice(cities)
    unit = random.choice(["", f", Apt {random.randint(1, 30)}"])
    return f"{random.randint(10, 9999)} {random.choice(streets)}{unit}, {city}, {state} {zip3}{random.randint(0, 99):02d}"
d["q18"] = col("q18", [f"{random.choice(us_first)} {random.choice(us_last)}" for _ in range(n)], True, "Q18")
d["q23"] = col("q23", [us_address() for _ in range(n)], True, "Q23")
d["q37"] = col("q37", [f"{c}, {s}" for c, s, _ in (random.choice(cities) for _ in range(n))], False, "Q37")
d["q38"] = col("q38", [f"{random.choice(['First National', 'Acme', 'Golden State', 'Lakeside', 'Riverside'])} {random.choice(['Bank', 'Hardware', 'Dental Group', 'Medical Center', 'Credit Union'])}" for _ in range(n)], False, "Q38")
d["q39"] = col("q39", [random.choice(streets) for _ in range(n)], False, "Q39")
# Identity numbers with checks: US Social Security numbers, payment cards and
# IBANs, behind question numbers; and a decoy of nine-digit order numbers,
# which an SSN's format alone cannot tell apart.
def ssn():
    area = random.choice([a for a in range(1, 900) if a != 666])
    return f"{area:03d}-{random.randint(1, 99):02d}-{random.randint(1, 9999):04d}"
def luhn_complete(body):
    digits = [int(c) for c in body][::-1]
    total = sum(d if i % 2 else (d * 2 - 9 if d * 2 > 9 else d * 2) for i, d in enumerate(digits))
    return body + str((10 - total % 10) % 10)
def card():
    prefix = random.choice(["4", "51", "55", "37", "6011", "60"])
    length = 15 if prefix == "37" else 16
    body = prefix + "".join(random.choice("0123456789") for _ in range(length - len(prefix) - 1))
    return luhn_complete(body)
def iban():
    account = "".join(random.choice("0123456789") for _ in range(18))
    moved = account + "DE00"
    number = int("".join(str(int(c, 36)) for c in moved))
    return f"DE{98 - number % 97:02d}{account}"
d["q24"] = col("q24", [ssn() for _ in range(n)], True, "Q24")
d["q25"] = col("q25", [card() for _ in range(n)], True, "Q25")
d["q26"] = col("q26", [iban() for _ in range(n)], True, "Q26")
d["q40"] = col("q40", [str(random.randint(10**8, 10**9 - 1)) for _ in range(n)], False, "Q40")
(out / "truth.json").write_text(json.dumps(truth, indent=1))
d.to_csv(out / "std" / "survey.csv", index=False)
d.to_stata(out / "std" / "survey.dta", write_index=False, variable_labels={k: v["label"] for k, v in truth.items()}, version=119)
d.to_excel(out / "other" / "survey.xlsx", index=False)
d.to_parquet(out / "other" / "survey.parquet", index=False)
d.to_csv(out / "other" / "survey.tsv", index=False, sep="\t")
d.to_json(out / "other" / "survey.jsonl", orient="records", lines=True)
# Qualtrics export: three header rows (name, question text, ImportId) and its own metadata columns
meta = pd.DataFrame({
    "ResponseId": [f"R_{random.randrange(10**14):015d}" for _ in range(n)],
    "IPAddress": [f"49.{random.randint(30,60)}.{random.randint(0,255)}.{random.randint(1,254)}" for _ in range(n)],
    "RecipientLastName": [a.split()[1] for a in name], "RecipientFirstName": [a.split()[0] for a in name],
    "RecipientEmail": d.q12, "LocationLatitude": d.gps_lat, "LocationLongitude": d.gps_lon,
    "Duration (in seconds)": [random.randint(200, 2000) for _ in range(n)], "Finished": [1] * n,
})
qs = d[["q13", "q15", "q20_text", "reason_visit", "satisfaction", "q30"]].copy()
qs.columns = ["Q1", "Q2", "Q3_TEXT", "Q4", "Q5", "Q6"]
q = pd.concat([meta, qs], axis=1)
text = {"ResponseId": "Response ID", "IPAddress": "IP Address", "RecipientLastName": "Recipient Last Name", "RecipientFirstName": "Recipient First Name",
        "RecipientEmail": "Recipient Email", "LocationLatitude": "Location Latitude", "LocationLongitude": "Location Longitude",
        "Duration (in seconds)": "Duration (in seconds)", "Finished": "Finished",
        "Q1": "What is the best number to reach you?", "Q2": "Who is the head of your household?", "Q3_TEXT": "Anything else you want to tell us?",
        "Q4": "Why did you visit the panchayat office?", "Q5": "How satisfied are you?", "Q6": "Did you attend the gram sabha?"}
rows = [list(q.columns), [text[c] for c in q.columns], [json.dumps({"ImportId": c}) for c in q.columns]]
pd.concat([pd.DataFrame(rows, columns=q.columns), q.astype(str)]).to_csv(out / "qualtrics" / "export.csv", index=False, header=False)
qt = {c: c in ("IPAddress", "RecipientLastName", "RecipientFirstName", "RecipientEmail", "LocationLatitude", "LocationLongitude", "Q1", "Q2", "Q3_TEXT") for c in q.columns}
(out / "truth_qualtrics.json").write_text(json.dumps(qt, indent=1))
print(len(d.columns), "columns;", sum(v["pii"] for v in truth.values()), "personal;", "qualtrics:", len(q.columns), "columns,", sum(qt.values()), "personal")
