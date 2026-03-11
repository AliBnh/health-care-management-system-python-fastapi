#!/usr/bin/env python3
"""
Aggregates Docker Compose vs Kubernetes benchmark results.

Reads:
results/docker/run_*.json
results/kubernetes/run_*.json

Produces:
results/comparison_summary.csv
results/all_runs.csv
"""

import json
import glob
import statistics
import csv
import os

def load_runs(directory):
    runs = []
    for f in sorted(glob.glob(os.path.join(directory, "run_*.json"))):
        with open(f) as file:
            runs.append(json.load(file))
    return runs


def summarize(runs, label):

    deploy_times = []
    build_times = []
    health_times = []
    successes = 0

    for r in runs:

        dep = r["deployment"]

        deploy_times.append(dep["total_time_ms"])
        build_times.append(dep["build_time_ms"])
        health_times.append(dep["health_ready_time_ms"])

        if dep["success"]:
            successes += 1

    failures = len(runs) - successes

    complexity = runs[0]["complexity"]

    return {
        "orchestrator": label,
        "runs": len(runs),

        "deploy_mean_s": round(statistics.mean(deploy_times)/1000,2),
        "deploy_median_s": round(statistics.median(deploy_times)/1000,2),
        "deploy_std_s": round(statistics.stdev(deploy_times)/1000,2) if len(deploy_times)>1 else 0,

        "deploy_min_s": round(min(deploy_times)/1000,2),
        "deploy_max_s": round(max(deploy_times)/1000,2),

        "build_mean_s": round(statistics.mean(build_times)/1000,2),
        "health_mean_s": round(statistics.mean(health_times)/1000,2),

        "success_count": successes,
        "failure_count": failures,
        "failure_rate_pct": round((failures/len(runs))*100,2),

        "config_files": complexity["config_files_count"],
        "config_lines": complexity["config_total_lines"],
        "cli_tools": complexity["cli_tools_count"]
    }


def main():

    docker_runs = load_runs("results/docker")
    k8s_runs = load_runs("results/kubernetes")

    docker_summary = summarize(docker_runs,"Docker Compose")
    k8s_summary = summarize(k8s_runs,"Kubernetes")

    print("\n====== BENCHMARK RESULTS ======\n")

    print(docker_summary)
    print(k8s_summary)

    os.makedirs("results",exist_ok=True)

    with open("results/comparison_summary.csv","w",newline="") as f:
        writer = csv.DictWriter(f,fieldnames=docker_summary.keys())
        writer.writeheader()
        writer.writerow(docker_summary)
        writer.writerow(k8s_summary)

    with open("results/all_runs.csv","w",newline="") as f:

        writer = csv.writer(f)

        writer.writerow([
            "orchestrator",
            "run_id",
            "deploy_ms",
            "build_ms",
            "health_ms",
            "success"
        ])

        for r in docker_runs:

            dep=r["deployment"]

            writer.writerow([
                "Docker Compose",
                r["run_id"],
                dep["total_time_ms"],
                dep["build_time_ms"],
                dep["health_ready_time_ms"],
                dep["success"]
            ])

        for r in k8s_runs:

            dep=r["deployment"]

            writer.writerow([
                "Kubernetes",
                r["run_id"],
                dep["total_time_ms"],
                dep["build_time_ms"],
                dep["health_ready_time_ms"],
                dep["success"]
            ])

    print("\nCSV files generated in results/")

if __name__ == "__main__":
    main()