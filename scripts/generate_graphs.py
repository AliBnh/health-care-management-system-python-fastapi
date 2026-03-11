import pandas as pd
import matplotlib.pyplot as plt
import os
import numpy as np

os.makedirs("results/figures",exist_ok=True)

df=pd.read_csv("results/all_runs.csv")
summary=pd.read_csv("results/comparison_summary.csv")

# BOX PLOT

docker=df[df.orchestrator=="Docker Compose"]["deploy_ms"]/1000
k8s=df[df.orchestrator=="Kubernetes"]["deploy_ms"]/1000

plt.figure(figsize=(8,5))

plt.boxplot([docker,k8s],labels=["Docker Compose","Kubernetes"])

plt.ylabel("Deployment Time (seconds)")
plt.title("Deployment Time Distribution")

plt.grid(True)

plt.savefig("results/figures/boxplot_deploy_time.png",dpi=200)

plt.close()

# BUILD vs HEALTH

labels=["Docker Compose","Kubernetes"]

build=summary["build_mean_s"]
health=summary["health_mean_s"]

x=np.arange(len(labels))

width=0.3

plt.figure(figsize=(8,5))

plt.bar(x-width/2,build,width,label="Build Time")
plt.bar(x+width/2,health,width,label="Health Ready")

plt.xticks(x,labels)

plt.ylabel("Seconds")

plt.title("Build vs Health Time")

plt.legend()

plt.grid(axis="y")

plt.savefig("results/figures/time_breakdown.png",dpi=200)

plt.close()

# COMPLEXITY

config=summary["config_lines"]
files=summary["config_files"]

plt.figure(figsize=(8,5))

plt.bar(labels,config)

plt.ylabel("Lines")

plt.title("Configuration Complexity")

plt.savefig("results/figures/config_complexity.png",dpi=200)

plt.close()

print("Graphs generated in results/figures")