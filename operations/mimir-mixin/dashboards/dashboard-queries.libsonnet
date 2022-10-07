{
  // This object contains common queries used in the Mimir dashboards.
  // These queries are NOT intended to be configurable or overriddeable via jsonnet,
  // but they're defined in a common place just to share them between different dashboards.
  queries:: {
    // Define the supported replacement variables in a single place. Most of them are frequently used.
    local variables = {
      gatewayMatcher: $.jobMatcher($._config.job_names.gateway),
      distributorMatcher: $.jobMatcher($._config.job_names.distributor),
      queryFrontendMatcher: $.jobMatcher($._config.job_names.query_frontend),
      rulerMatcher: $.jobMatcher($._config.job_names.ruler),
      alertmanagerMatcher: $.jobMatcher($._config.job_names.alertmanager),
      namespaceMatcher: $.namespaceMatcher(),
      writeHTTPRoutesRegex: $.queries.write_http_routes_regex,
      writeGRPCRoutesRegex: $.queries.write_grpc_routes_regex,
      readHTTPRoutesRegex: $.queries.read_http_routes_regex,
      perClusterLabel: $._config.per_cluster_label,
    },

    write_http_routes_regex: 'api_(v1|prom)_push|otlp_v1_metrics',
    write_grpc_routes_regex: '/distributor.Distributor/Push|/httpgrpc.*',
    read_http_routes_regex: '(prometheus|api_prom)_api_v1_.+',

    gateway: {
      writeRequestsPerSecond: 'cortex_request_duration_seconds_count{%s, route=~"%s"}' % [$.jobMatcher($._config.job_names.gateway), $.queries.write_http_routes_regex],
      readRequestsPerSecond: 'cortex_request_duration_seconds_count{%s, route=~"%s"}' % [$.jobMatcher($._config.job_names.gateway), $.queries.read_http_routes_regex],

      // Write failures rate as percentage of total requests.
      writeFailuresRate: |||
        (
            sum(rate(cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(writeHTTPRoutesRegex)s",status_code=~"5.*"}[$__rate_interval]))
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
        )
        /
        sum(rate(cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(writeHTTPRoutesRegex)s"}[$__rate_interval]))
      ||| % variables,

      // Read failures rate as percentage of total requests.
      readFailuresRate: |||
        (
            sum(rate(cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(readHTTPRoutesRegex)s",status_code=~"5.*"}[$__rate_interval]))
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
        )
        /
        sum(rate(cortex_request_duration_seconds_count{%(gatewayMatcher)s, route=~"%(readHTTPRoutesRegex)s"}[$__rate_interval]))
      ||| % variables,
    },

    distributor: {
      writeRequestsPerSecond: 'cortex_request_duration_seconds_count{%s, route=~"%s|%s"}' % [$.jobMatcher($._config.job_names.distributor), $.queries.write_grpc_routes_regex, $.queries.write_http_routes_regex],
      samplesPerSecond: 'sum(%(group_prefix_jobs)s:cortex_distributor_received_samples:rate5m{%(job)s})' % (
        $._config {
          job: $.jobMatcher($._config.job_names.distributor),
        }
      ),
      exemplarsPerSecond: 'sum(%(group_prefix_jobs)s:cortex_distributor_received_exemplars:rate5m{%(job)s})' % (
        $._config {
          job: $.jobMatcher($._config.job_names.distributor),
        }
      ),

      // Write failures rate as percentage of total requests.
      writeFailuresRate: |||
        (
            # gRPC errors are not tracked as 5xx but "error".
            sum(rate(cortex_request_duration_seconds_count{%(distributorMatcher)s, route=~"%(writeGRPCRoutesRegex)s|%(writeHTTPRoutesRegex)s",status_code=~"5.*|error"}[$__rate_interval]))
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
        )
        /
        sum(rate(cortex_request_duration_seconds_count{%(distributorMatcher)s, route=~"%(writeGRPCRoutesRegex)s|%(writeHTTPRoutesRegex)s"}[$__rate_interval]))
      ||| % variables,
    },

    query_frontend: {
      readRequestsPerSecond: 'cortex_request_duration_seconds_count{%s, route=~"%s"}' % [$.jobMatcher($._config.job_names.query_frontend), $.queries.read_http_routes_regex],
      instantQueriesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%s,route=~"(prometheus|api_prom)_api_v1_query"}[$__rate_interval]))' % $.jobMatcher($._config.job_names.query_frontend),
      rangeQueriesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%s,route=~"(prometheus|api_prom)_api_v1_query_range"}[$__rate_interval]))' % $.jobMatcher($._config.job_names.query_frontend),
      labelQueriesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%s,route=~"(prometheus|api_prom)_api_v1_label.*"}[$__rate_interval]))' % $.jobMatcher($._config.job_names.query_frontend),
      seriesQueriesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%s,route=~"(prometheus|api_prom)_api_v1_series"}[$__rate_interval]))' % $.jobMatcher($._config.job_names.query_frontend),
      otherQueriesPerSecond: 'sum(rate(cortex_request_duration_seconds_count{%s,route=~"(prometheus|api_prom)_api_v1_.*",route!~".*(query|query_range|label.*|series)"}[$__rate_interval]))' % $.jobMatcher($._config.job_names.query_frontend),

      // Read failures rate as percentage of total requests.
      readFailuresRate: |||
        (
            sum(rate(cortex_request_duration_seconds_count{%(queryFrontendMatcher)s, route=~"%(readHTTPRoutesRegex)s",status_code=~"5.*"}[$__rate_interval]))
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
        )
        /
        sum(rate(cortex_request_duration_seconds_count{%(queryFrontendMatcher)s, route=~"%(readHTTPRoutesRegex)s"}[$__rate_interval]))
      ||| % variables,
    },

    ruler: {
      evaluations: {
        successPerSecond:
          |||
            sum(rate(cortex_prometheus_rule_evaluations_total{%s}[$__rate_interval]))
            -
            sum(rate(cortex_prometheus_rule_evaluation_failures_total{%s}[$__rate_interval]))
          ||| % [$.jobMatcher($._config.job_names.ruler), $.jobMatcher($._config.job_names.ruler)],
        failurePerSecond: 'sum(rate(cortex_prometheus_rule_evaluation_failures_total{%s}[$__rate_interval]))' % $.jobMatcher($._config.job_names.ruler),
        missedIterationsPerSecond: 'sum(rate(cortex_prometheus_rule_group_iterations_missed_total{%s}[$__rate_interval]))' % $.jobMatcher($._config.job_names.ruler),
        latency:
          |||
            sum (rate(cortex_prometheus_rule_evaluation_duration_seconds_sum{%s}[$__rate_interval]))
              /
            sum (rate(cortex_prometheus_rule_evaluation_duration_seconds_count{%s}[$__rate_interval]))
          ||| % [$.jobMatcher($._config.job_names.ruler), $.jobMatcher($._config.job_names.ruler)],

        // Rule evaluation failures rate as percentage of total requests.
        failuresRate: |||
          (
            (
                sum(rate(cortex_prometheus_rule_evaluation_failures_total{%(rulerMatcher)s}[$__rate_interval]))
                +
                # Consider missed evaluations as failures.
                sum(rate(cortex_prometheus_rule_group_iterations_missed_total{%(rulerMatcher)s}[$__rate_interval]))
            )
            or
            # Handle the case no failure has been tracked yet.
            vector(0)
          )
          /
          sum(rate(cortex_prometheus_rule_evaluations_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,
      },
      notifications: {
        // Notifications / sec successfully sent to the Alertmanager.
        successPerSecond: |||
          sum(rate(cortex_prometheus_notifications_sent_total{%(rulerMatcher)s}[$__rate_interval]))
            -
          sum(rate(cortex_prometheus_notifications_errors_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,

        // Notifications / sec failed to be sent to the Alertmanager.
        failurePerSecond: |||
          sum(rate(cortex_prometheus_notifications_errors_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,

        // Notifications failed to be sent to the Alertmanager as percentage of total notifications attempted.
        failuresRate: |||
          sum(rate(cortex_prometheus_notifications_errors_total{%(rulerMatcher)s}[$__rate_interval]))
          /
          sum(rate(cortex_prometheus_notifications_sent_total{%(rulerMatcher)s}[$__rate_interval]))
        ||| % variables,
      },
    },

    alertmanager: {
      notifications: {
        // Notifications / sec successfully delivered by the Alertmanager to the receivers.
        successPerSecond: |||
          sum(%(perClusterLabel)s_job_integration:cortex_alertmanager_notifications_total:rate5m{%(alertmanagerMatcher)s})
          -
          sum(%(perClusterLabel)s_job_integration:cortex_alertmanager_notifications_failed_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,

        // Notifications / sec failed to be delivered by the Alertmanager to the receivers.
        failurePerSecond: |||
          sum(%(perClusterLabel)s_job_integration:cortex_alertmanager_notifications_failed_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,

        // Notifications failed to be sent by the Alertmanager to the receivers as percentage of total notifications attempted.
        failuresRate: |||
          sum(%(perClusterLabel)s_job_integration:cortex_alertmanager_notifications_failed_total:rate5m{%(alertmanagerMatcher)s})
          /
          sum(%(perClusterLabel)s_job_integration:cortex_alertmanager_notifications_total:rate5m{%(alertmanagerMatcher)s})
        ||| % variables,
      },
    },

    storage: {
      successPerSecond: |||
        sum(rate(thanos_objstore_bucket_operations_total{%(namespaceMatcher)s}[$__rate_interval]))
        -
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,
      failurePerSecond: |||
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,

      // Object storage operation failures rate as percentage of total operations.
      failuresRate: |||
        sum(rate(thanos_objstore_bucket_operation_failures_total{%(namespaceMatcher)s}[$__rate_interval]))
        /
        sum(rate(thanos_objstore_bucket_operations_total{%(namespaceMatcher)s}[$__rate_interval]))
      ||| % variables,
    },
  },
}