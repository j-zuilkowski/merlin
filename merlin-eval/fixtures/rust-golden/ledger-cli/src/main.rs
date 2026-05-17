//! ledger-cli - `add <cents> <category>`, `total [category]`, `report`.
//! State persists to `./ledger.txt` (one `amount_cents\tcategory` per line).
use ledger::Ledger;
use std::process::ExitCode;

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(out) => {
            print!("{out}");
            ExitCode::SUCCESS
        }
        Err(msg) => {
            eprintln!("error: {msg}");
            ExitCode::FAILURE
        }
    }
}

const STORE: &str = "ledger.txt";

fn run(args: &[String]) -> Result<String, String> {
    let cmd = args.first().map(String::as_str).unwrap_or("");
    match cmd {
        "add" => {
            let cents_arg = args.get(1).ok_or("usage: add <cents> <category>")?;
            let category = args.get(2).ok_or("usage: add <cents> <category>")?;
            let cents: i64 = cents_arg.parse().map_err(|_| {
                format!("invalid amount '{cents_arg}' - expected an integer of cents")
            })?;
            append(cents, category)?;
            Ok(format!("added {cents} to {category}\n"))
        }
        "total" => {
            let ledger = load()?;
            if let Some(category) = args.get(1) {
                Ok(format!("{}\n", ledger.lookup_total(category)))
            } else {
                Ok(format!("{}\n", ledger.total()))
            }
        }
        "report" => {
            let ledger = load()?;
            let mut out = String::new();
            for c in ledger.categories() {
                out.push_str(&format!("{c}: {}\n", ledger.total_for(&c)));
            }
            Ok(out)
        }
        other => Err(format!("unknown command '{other}'")),
    }
}

fn append(cents: i64, category: &str) -> Result<(), String> {
    use std::io::Write;
    let mut f = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(STORE)
        .map_err(|e| e.to_string())?;
    writeln!(f, "{cents}\t{category}").map_err(|e| e.to_string())
}

fn load() -> Result<Ledger, String> {
    let mut ledger = Ledger::new();
    let text = match std::fs::read_to_string(STORE) {
        Ok(t) => t,
        Err(_) => return Ok(ledger),
    };
    for line in text.lines() {
        let mut parts = line.splitn(2, '\t');
        if let (Some(c), Some(cat)) = (parts.next(), parts.next()) {
            if let Ok(cents) = c.parse::<i64>() {
                ledger.add(cents, cat);
            }
        }
    }
    Ok(ledger)
}
