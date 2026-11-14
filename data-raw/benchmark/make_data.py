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
(out / "truth.json").write_text(json.dumps(truth, indent=1))
d.to_csv(out / "std" / "survey.csv", index=False)
d.to_stata(out / "std" / "survey.dta", write_index=False, variable_labels={k: v["label"] for k, v in truth.items()}, version=118)
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
