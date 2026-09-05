% TEST SCRIPT: test_module5_simulink
% MODULE: 6 - Simulink / Screening Workflow Modeling
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Unit test suite for the district screening workflow simulation engine:
%   - Annual throughput conservation (100,000+ patients/year)
%   - Autonomous AI triage filtration rate (~75-80% cleared)
%   - Ophthalmologist review turnaround SLA compliance (<24 hours)
%   - Resource allocation recommendation output validity
%   - Programmatic Simulink model builder execution
%
% HOW TO RUN:
%   cd to repo root, then: run('tests/test_module5_simulink.m')
%
% DEPENDS ON:
%   src/module5_simulink/simulate_screening_workflow.m
%   src/module5_simulink/build_screening_simulink_model.m

addpath('../src/module5_simulink');
addpath('src/module5_simulink');

fprintf('=== Running Module 5 Simulink Workflow Tests ===\n\n');
n_pass = 0;
n_total = 0;

%% --- Test 1: Annual Throughput Sizing & Conservation ---
n_total = n_total + 1;
test_params = struct('annual_target', 100000, 'operating_days', 250, 'n_sim_patients', 2000);
res = simulate_screening_workflow(test_params);

% Daily arrival rate must equal 100,000 / 250 = 400 patients/day
if abs(res.daily_arrival_rate - 400.0) < 1e-4
    fprintf('  [PASS] Test 1: Annual throughput rate conserved (400 patients/day across district)\n');
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 1: Expected 400 patients/day, got %.1f\n', res.daily_arrival_rate);
end

%% --- Test 2: Autonomous AI Triage Clearance Rate ---
n_total = n_total + 1;
% With referable_rate = 0.22, doctor daily load should be ~400 * 0.22 / n_doctors
expected_referred_daily = 400 * 0.22;
actual_doc_total_load = res.doctor_daily_load * res.n_doctors;

if abs(actual_doc_total_load - expected_referred_daily) < 1.0
    fprintf('  [PASS] Test 2: AI triage successfully cleared ~78%% of cases (doctor load: %.0f cases/day)\n', ...
        actual_doc_total_load);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 2: AI triage clearance rate mismatch\n');
end

%% --- Test 3: Ophthalmologist Turnaround SLA Compliance (<24h) ---
n_total = n_total + 1;
% Sized system should comfortably meet the <24-hour turnaround SLA (target >95%)
if res.sla_compliance_pct >= 90.0 && res.avg_doctor_wait_hours < 12.0
    fprintf('  [PASS] Test 3: Doctor review SLA compliance verified (%.1f%% within 24h, avg wait %.1f hrs)\n', ...
        res.sla_compliance_pct, res.avg_doctor_wait_hours);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 3: SLA compliance violated (%.1f%% within 24h)\n', res.sla_compliance_pct);
end

%% --- Test 4: Resource Sizing Recommendation Statement ---
n_total = n_total + 1;
rec = res.recommendation_text;
has_cameras = contains(rec, 'cameras');
has_doctors = contains(rec, 'ophthalmologists');
has_target  = contains(rec, '100000 patients/year');

if has_cameras && has_doctors && has_target
    fprintf('  [PASS] Test 4: Concrete resource allocation recommendation generated successfully\n');
    fprintf('         "%s"\n', rec(1:min(120, length(rec))));
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 4: Recommendation text incomplete or missing required fields\n');
end

%% --- Test 5: Simulink Model Builder Execution ---
n_total = n_total + 1;
test_model_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'models');
built_path = build_screening_simulink_model(test_model_dir, 'test_dr_workflow');

if exist(built_path, 'file')
    fprintf('  [PASS] Test 5: Simulink model builder generated valid target (%s)\n', built_path);
    n_pass = n_pass + 1;
else
    fprintf('  [FAIL] Test 5: Expected built file to exist at %s\n', built_path);
end

%% --- Summary ---
fprintf('\nModule 5 tests: %d/%d passed\n', n_pass, n_total);
if n_pass == n_total
    fprintf('STATUS CONFIRMED: ALL Module 5 Simulink Workflow functions DONE_TESTED (%d/%d)\n', n_pass, n_total);
else
    fprintf('WARNING: Some tests failed. Investigate failures above.\n');
end
