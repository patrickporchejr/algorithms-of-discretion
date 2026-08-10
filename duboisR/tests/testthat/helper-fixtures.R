# Shared in-memory fixtures for tests. Never touches the real (gitignored,
# 650MB) data/processed/audit_ready_stops.csv — everything here is
# synthetic, schema-matched data from simulate_stops().

dubois_test_stops <- function(n = 500, seed = 1) {
  simulate_stops(n = n, seed = seed)
}
