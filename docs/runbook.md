# Operational Runbook: BankingCore

## Incident Response & Rollback Procedure

### 1. Severity Levels
- **Sev-1**: Core transaction failure or double-spend detected in production.
- **Sev-2**: Degraded network retry loops or token refresh starvation.

### 2. Rollback Procedure
If a production deployment of BankingCore exhibits regressions or API incompatibilities:
1. Identify the last known stable Git tag (e.g. `v1.0.0`).
2. Trigger the automated rollback workflow:
   ```bash
   git checkout main
   git revert -m 1 <commit-hash>
   git push origin main
   ```
3. For mobile client rollbacks in TestFlight / App Store:
   - Halt active phased release in App Store Connect.
   - Re-enable the previous binary build in TestFlight.
   - Flush client-side cache and reset token interceptors.
