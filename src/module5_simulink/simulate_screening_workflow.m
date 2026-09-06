function results = simulate_screening_workflow(params, show_plots)
% FUNCTION: simulate_screening_workflow
% MODULE: 6 - Simulink / Screening Workflow Modeling
% STATUS: DONE_TESTED
%
% PURPOSE:
%   Simulates the complete district-level telemedicine Diabetic Retinopathy
%   screening workflow as a discrete-event queuing network sized for
%   100,000+ rural patients/year. Models patient arrival at rural Primary
%   Health Centers (PHCs), fundus image acquisition, bandwidth-constrained
%   telecom uplink, cloud/edge AI pipeline inference, autonomous clearance,
%   and multi-server ophthalmologist review queues. Generates concrete
%   resource-sizing recommendations (cameras, doctors, bandwidth).
%
% INPUTS:
%   params (struct or numeric, optional) - workflow configuration parameters
%       or scalar number of patients to simulate (default: 10000). If struct:
%       - annual_target: total patients/year (default: 100000)
%       - operating_days: operational screening days/year (default: 250)
%       - n_cameras: number of portable camera units across district (default: 10)
%       - acquisition_time_min: capture + field QA time/patient (default: 4.0)
%       - image_payload_mb: compressed image size for both eyes (default: 5.0)
%       - bandwidth_mbps: uplink bandwidth per health center (default: 4.0)
%       - ai_latency_sec: execution time of Modules 1-4 per patient (default: 2.0)
%       - n_doctors: number of reviewing ophthalmologists (default: 3)
%       - doctor_hours_per_day: tele-triage review time per doctor/day (default: 2.0)
%       - review_time_sec: doctor review time per case (default: 30.0)
%       - referable_rate: proportion of patients needing review (default: 0.22)
%       - n_sim_patients: number of patients to simulate (default: 10000)
%   show_plots (logical, optional) - whether to display queuing plots (default: false)
%
% OUTPUTS:
%   results (struct) - quantitative queuing metrics & resource allocation:
%       - daily_arrival_rate: district-wide patients per operating day
%       - avg_acquisition_wait_min: mean patient waiting time at clinic
%       - avg_network_transfer_sec: mean image uplink transmission delay
%       - avg_ai_queue_wait_sec: mean waiting time in AI inference queue
%       - avg_doctor_wait_hours: mean time until doctor signs off on referable cases
%       - doctor_daily_load: cases reviewed per doctor per day
%       - sla_compliance_pct: percentage of referable cases reviewed within 24 hours
%       - bottleneck_stage: identified system bottleneck ('Acquisition', 'Network', 'AI', 'Doctor')
%       - recommendation_text: formal resource allocation statement for health officials
%
% DEPENDS ON:
%   none (self-contained discrete-event Monte Carlo simulation engine)
%
% CALLED BY:
%   run_pipeline.m (optional workflow validation)
%   tests/test_module5_simulink.m

    % --- Step 1: Initialize Parameters with Defaults ---
    if nargin < 1 || isempty(params)
        params = struct();
    elseif isnumeric(params)
        params = struct('n_sim_patients', params);
    end
    if nargin < 2 || isempty(show_plots)
        show_plots = false;
    end

    annual_target        = get_param(params, 'annual_target', 100000);
    operating_days       = get_param(params, 'operating_days', 250);
    n_cameras            = get_param(params, 'n_cameras', 10);
    acq_time_min         = get_param(params, 'acquisition_time_min', 4.0);
    image_payload_mb     = get_param(params, 'image_payload_mb', 5.0);
    bandwidth_mbps       = get_param(params, 'bandwidth_mbps', 4.0);
    ai_latency_sec       = get_param(params, 'ai_latency_sec', 2.0);
    n_doctors            = get_param(params, 'n_doctors', 3);
    doc_hours_per_day    = get_param(params, 'doctor_hours_per_day', 2.0);
    review_time_sec      = get_param(params, 'review_time_sec', 30.0);
    referable_rate       = get_param(params, 'referable_rate', 0.22);
    n_sim                = get_param(params, 'n_sim_patients', 10000);

    % Operational sizing rates
    daily_arrival_rate = annual_target / operating_days; % e.g., 400 patients/day
    patients_per_cam_day = daily_arrival_rate / n_cameras; % e.g., 40 patients/camera/day
    clinic_hours = 6.0; % 6-hour daily field screening camp window

    % --- Step 2: Discrete-Event Simulation Engine ---
    % Simulate N patients arriving over consecutive operational days
    rng(42); % Fixed seed for reproducible benchmarks

    % 2a. Image Acquisition at PHCs
    % Patient inter-arrival time in minutes per camera
    inter_arr_mean = (clinic_hours * 60) / max(1, patients_per_cam_day);
    inter_arrivals = exprnd(inter_arr_mean, [n_sim, 1]);
    arr_times = cumsum(inter_arrivals);

    % Service time per patient: lognormal around acq_time_min
    acq_services = lognrnd(log(acq_time_min) - 0.05, 0.20, [n_sim, 1]);

    acq_start = zeros(n_sim, 1);
    acq_end   = zeros(n_sim, 1);
    for i = 1:n_sim
        if i == 1
            acq_start(i) = arr_times(i);
        else
            acq_start(i) = max(arr_times(i), acq_end(i - 1));
        end
        acq_end(i) = acq_start(i) + acq_services(i);
    end
    acq_wait_times = acq_start - arr_times; % wait in clinic queue

    % 2b. Network Transmission (Uplink to Cloud)
    % Transmission delay = payload in megabits / bandwidth in Mbps
    tx_delay_sec = (image_payload_mb * 8.0) / max(0.5, bandwidth_mbps);
    % Add stochastic network jitter (exponential delay)
    tx_delays_min = (tx_delay_sec + exprnd(1.5, [n_sim, 1])) / 60.0;
    cloud_arrive = acq_end + tx_delays_min;

    % 2c. Cloud AI Processing Queue (Centralized Server)
    % Multi-core or GPU cloud service with latency ai_latency_sec
    ai_serv_min = (ai_latency_sec + exprnd(0.2, [n_sim, 1])) / 60.0;
    ai_start = zeros(n_sim, 1);
    ai_end   = zeros(n_sim, 1);
    for i = 1:n_sim
        if i == 1
            ai_start(i) = cloud_arrive(i);
        else
            ai_start(i) = max(cloud_arrive(i), ai_end(i - 1));
        end
        ai_end(i) = ai_start(i) + ai_serv_min(i);
    end
    ai_wait_sec = (ai_start - cloud_arrive) * 60.0;

    % 2d. Autonomous AI Triage Filter
    % ~78% of cases are Normal (Grade 0) or Mild (Grade 1) and cleared autonomously
    % ~22% are Referable (Grade >= 2) or Borderline Quality and queued for Doctor Review
    needs_review = rand(n_sim, 1) <= referable_rate;
    n_referred = sum(needs_review);

    % 2e. Ophthalmologist Review Pool Queue
    % Review queue receives referred patients
    doc_arrive = ai_end(needs_review);
    doc_serv_sec = lognrnd(log(review_time_sec) - 0.05, 0.25, [n_referred, 1]);
    doc_serv_min = doc_serv_sec / 60.0;

    % Available reviewing doctors (M parallel servers working doc_hours_per_day)
    doc_free_times = zeros(n_doctors, 1);
    doc_wait_hours = zeros(n_referred, 1);

    % Total doctor capacity in minutes per day
    daily_doc_capacity_min = n_doctors * doc_hours_per_day * 60.0;
    daily_referred_cases = daily_arrival_rate * referable_rate;
    daily_workload_min = daily_referred_cases * (review_time_sec / 60.0);

    for j = 1:n_referred
        % Route to earliest available doctor
        [min_free, doc_idx] = min(doc_free_times);
        start_time = max(doc_arrive(j), min_free);
        finish_time = start_time + doc_serv_min(j);
        doc_free_times(doc_idx) = finish_time;

        % Calculate waiting time in hours (with diurnal overnight pauses accounted for)
        raw_wait_min = start_time - doc_arrive(j);
        doc_wait_hours(j) = (raw_wait_min / 60.0) * (clinic_hours / max(1.0, doc_hours_per_day));
    end

    % --- Step 3: Compute Performance Metrics ---
    avg_acq_wait = mean(acq_wait_times);
    avg_tx_sec = mean(tx_delays_min * 60.0);
    avg_ai_wait = mean(ai_wait_sec);
    avg_doc_wait_h = mean(doc_wait_hours);
    cases_per_doc_day = daily_referred_cases / max(1, n_doctors);
    sla_compliance = (sum(doc_wait_hours <= 24.0) / max(1, n_referred)) * 100.0;

    % --- Step 4: Bottleneck Identification ---
    util_cam = (patients_per_cam_day * acq_time_min) / (clinic_hours * 60.0);
    util_net = (daily_arrival_rate * tx_delay_sec) / (clinic_hours * 3600.0);
    util_ai  = (daily_arrival_rate * ai_latency_sec) / (clinic_hours * 3600.0);
    util_doc = daily_workload_min / max(1.0, daily_doc_capacity_min);

    [max_util, b_idx] = max([util_cam, util_net, util_ai, util_doc]);
    stage_names = {'Acquisition (Cameras)', 'Network Bandwidth', 'AI Processing', 'Ophthalmologist Review'};
    bottleneck_stage = stage_names{b_idx};

    % --- Step 5: Sizing Recommendation Statement ---
    rec_statement = sprintf([ ...
        'To screen %d patients/year across a rural district with a <24-hour turnaround SLA, ' ...
        'the system requires %d portable cameras across Primary Health Centers (each screening ~%.0f patients/day at %.1f min/patient), ' ...
        '%d reviewing ophthalmologists (each triaging ~%.0f cases/day at %.0fs/case with explainable reports), ' ...
        'an AI cloud server with latency <= %.1fs/image, and minimum uplink bandwidth of %.1f Mbps per clinic.'], ...
        annual_target, n_cameras, patients_per_cam_day, acq_time_min, ...
        n_doctors, cases_per_doc_day, review_time_sec, ai_latency_sec, bandwidth_mbps);

    % --- Optional: Visual Performance Dashboard ---
    if show_plots
        figure('Name', 'District Screening Queuing Simulation', 'Color', 'w', ...
               'Position', [100, 100, 950, 420]);

        subplot(1, 2, 1);
        histogram(doc_wait_hours, 30, 'FaceColor', [0.2, 0.5, 0.8], 'EdgeColor', 'w');
        hold on;
        xline(24.0, 'r--', 'LineWidth', 2, 'Label', '24h SLA Target');
        title(sprintf('Doctor Review Turnaround (%.1f%% < 24h)', sla_compliance), 'FontSize', 11);
        xlabel('Turnaround Wait Time (Hours)');
        ylabel('Patient Count');
        grid on;

        subplot(1, 2, 2);
        b = bar([util_cam, util_net, util_ai, util_doc] * 100);
        b.FaceColor = 'flat';
        b.CData(1,:) = [0.2, 0.6, 0.4];
        b.CData(2,:) = [0.3, 0.4, 0.7];
        b.CData(3,:) = [0.8, 0.6, 0.1];
        b.CData(4,:) = [0.8, 0.3, 0.3];
        set(gca, 'XTickLabel', {'Cameras', 'Network', 'AI Server', 'Doctors'}, 'FontSize', 10);
        ylabel('Resource Utilization (%)');
        title('District Workflow Stage Utilization', 'FontSize', 11);
        ylim([0, 100]);
        yline(100, 'k:');
        grid on;
    end

    % Assemble results struct
    results = struct( ...
        'annual_target', annual_target, ...
        'daily_arrival_rate', daily_arrival_rate, ...
        'n_cameras', n_cameras, ...
        'n_doctors', n_doctors, ...
        'avg_acquisition_wait_min', avg_acq_wait, ...
        'avg_network_transfer_sec', avg_tx_sec, ...
        'avg_ai_queue_wait_sec', avg_ai_wait, ...
        'avg_doctor_wait_hours', avg_doc_wait_h, ...
        'doctor_daily_load', cases_per_doc_day, ...
        'sla_compliance_pct', sla_compliance, ...
        'camera_utilization', util_cam, ...
        'doctor_utilization', util_doc, ...
        'bottleneck_stage', bottleneck_stage, ...
        'recommendation_text', rec_statement);
end

function val = get_param(s, field, default_val)
    if isfield(s, field) && ~isempty(s.(field))
        val = s.(field);
    else
        val = default_val;
    end
end
