# Literature Review Report — Local Crossref Corpus (15 query files, `project/lit/`)

**Scope.** This report is built **exclusively** from the 15 local files `q01_pta_flexible.txt` … `q15_operability.txt`. No web search, no external knowledge introduced as evidence. Every number and claim is traceable to a line in one of those files.

**Corpus statistics (verified programmatically).**

| File | Raw entries | Non-empty abstracts |
|---|---|---|
| q01_pta_flexible | 25 | 5 |
| q02_hb_dynamic | 19 | 1 |
| q03_hb_mpc | 13 | 2 |
| q04_pta_lcoa | 22 | 4 |
| q05_pta_sizing | 25 | 3 |
| q06_pta_dispatch | 19 | 6 |
| q07_multi_stack | 16 | 1 |
| q08_h2_storage | 17 | 2 |
| q09_curtail | 23 | 2 |
| q10_metrics | 19 | 4 |
| q11_indicator_sel | 17 | 6 |
| q12_cycling | 14 | 2 |
| q13_chn_ammonia | 17 | 5 |
| q14_review_pta | 22 | 3 |
| q15_operability | 6 | 1 |
| **TOTAL** | **274** | **47 (17.2%)** |

**Critical meta-finding #1 — the corpus is mostly title-only.** 227 of 274 entries (82.8%) have an empty `ABSTRACT` field. Consequently, for the overwhelming majority of on-topic papers I can report *what the title claims* but **cannot** report min loads, ramp rates, LCOA values, or constraint formulations, because those fields do not exist in these files. I mark every such item `[title-only]` and I do **not** infer content from titles.

**Critical meta-finding #2 — query quality is highly uneven.** q13 ("China green ammonia Inner Mongolia…") returned potato genetics, ophthalmology and soil-amendment papers; q09 ("curtailment grid interaction green ammonia plant electricity market") returned an EU energy-law textbook and its 15 chapter splits; q10 ("operational stability metric…") returned 9 *eLife* peer-review artifacts about archaeal membranes and olfactory memory; q15 ("operability constraints scheduling chemical plant…") returned 6 entries total, one about KRAS G12C covalent inhibitors. Searches q09 and q15 must be regarded as **failed queries**.

**Critical meta-finding #3 — a large fraction of entries are Crossref editorial artifacts**, not papers (peer-review reports, decision letters, author responses) and 4 are grant records. Counted as ~44 entries (~16%).

---

# PART A — RELEVANCE-TRIAGED INVENTORY

Deduplicated by DOI/title. `[title-only]` = no abstract in these files, so the contribution is **not assessable** from this corpus; I report only the title's stated subject. Approximate unique-work count after dedupe: ~200 works from 274 entries; ~84 were triaged in, ~120 dropped.

## A1. Power-to-ammonia / green ammonia system design, sizing, techno-economic (LCOA) — 15 works

1. **Wang, Walsh, Longden & Palmer (2022 preprint; 2023 journal)** — *Optimising renewable generation configurations of off-grid green ammonia production systems considering Haber-Bosch flexibility*. Preprint: `10.31223/x5vp9g`; journal version *Energy Conversion and Management*: `10.1016/j.enconman.2023.116790` (CITED 130). Australian hydrogen-hub siting study; the abstract's contribution is that "most of the pre-identified hydrogen hubs in each state and territory of Australia can produce cost-competitive green ammonia **providing the electrolysis and Haber-Bosch processes are partially flexible** to cope with the variability of renewables", and that "Flexible operation reduces energy curtailment and leads to lower storage capacity requirements using batteries or hydrogen storage". **Flexibility is assumed, not modelled at the constraint level in the abstract** — no min load or ramp rate is quoted.
2. **Jahanbakhsh (2025)** — *Techno-Economic Analysis of Renewable Energy-Powered Ammonia Production*. SSRN, `10.2139/ssrn.5166467`. Numerical optimisation of a Denmark wind/PV/electrolyser/battery/H₂-storage system minimising LCOA subject to reliability. **Only paper in the corpus giving a full sizing vector plus LCOA simultaneously** (see Part B).
3. **Pistolesi, Giaconia, Bassano & De Falco (2025)** — *Flexible Green Ammonia Production: Impact of Process Design on the Levelized Cost of Ammonia*. *Fuels*, `10.3390/fuels6020039` (CITED 15). LCOA sensitivity analysis for Italy (ALK electrolysis + cryogenic ASU + Haber–Bosch), sweeping "renewable source peak power, Haber-Bosch reactor flexibility, energy mix, electrochemical and hydrogen storage". **The only paper in the corpus that operationalises a minimum-load-like parameter explicitly**: "a flexibility factor (**ratio between the minimum operating capacity and the nominal capacity of the plant**) of 20%".
4. **Pfromm & Aframehr (2022)** — *Green ammonia from air, water, and renewable electricity: Energy costs using natural gas reforming, solid oxide electrolysis, liquid water electrolysis, chemical looping, or a Haber–Bosch loop*. *Journal of Renewable and Sustainable Energy*, `10.1063/5.0101709` (CITED 12). Comparative energy-cost study for a 1000 t/day NH₃ plant across H₂ supply routes; conclusion is that energy costs "are not substantially different for the alternatives investigated here".
5. **Pozo, Sauma & Bolado-Lavín (2025)** — *Levelized cost analysis for renewable ammonia production in Chile*. *Energy*, `10.1016/j.energy.2025.137554` (CITED 3). `[title-only]`
6. **Özmen & Ng (2025)** — *Predictive modeling for levelized cost of green ammonia*. *Applied Energy*, `10.1016/j.apenergy.2025.126399` (CITED 8). `[title-only]` — title suggests a data-driven LCOA surrogate.
7. **Sun, Sun & Li (2025)** — *Techno-economic evaluation of green ammonia synthesis for renewable energy storage using rigorous models*. *Energy*, `10.1016/j.energy.2025.138068` (CITED 17). `[title-only]`
8. **Genge & Müsgens (2026)** — *Green ammonia: A techno-economic supply chain optimization*. *Journal of Cleaner Production*, `10.1016/j.jclepro.2026.148592` (CITED 3). `[title-only]`
9. **Palys, Moot, Parvathikar & Zhang (2025)** — *Techno-economic optimization of flexible distributed green ammonia production*. SSRN, `10.2139/ssrn.5527555`. `[title-only]`
10. **Zhang, Wen, Huang & Jin (2024)** — *Techno-Economic Optimization of Renewable Power to Ammonia System Based on Flexible Process*. SSRN, `10.2139/ssrn.4894107`. `[title-only]`
11. **Zhao & Lou (2026)** — *Transforming energy-intensive loads into flexible resources: A scenario-based multi-objective planning model for renewable power-to-ammonia system with integrated flexibility*. *Energy*, `10.1016/j.energy.2026.142175`. `[title-only]` — title indicates scenario-based multi-objective planning.
12. **Zhou, Tong, Wang & Xu (2025)** — *Flexible design and operation of off-grid green ammonia systems with gravity energy storage under long-term renewable power uncertainty*. *Applied Energy*, `10.1016/j.apenergy.2025.125629` (CITED 30). `[title-only]`
13. **Li, Ji & Wang (2026)** — *Two-layer capacity optimization configuration of wind-photovoltaic-hydrogen-ammonia coupling system based on Kriging, NSGA-III algorithm, and stochastic MCDM*. *Energy*, `10.1016/j.energy.2026.142307`. `[title-only]`
14. **Armijo & Philibert (2020)** — *Flexible production of green hydrogen and ammonia from variable solar and wind energy: Case study of Chile and Argentina*. *IJHE*, `10.1016/j.ijhydene.2019.11.028` (**CITED 568** — most-cited on-topic work in the corpus). `[title-only]`
15. **Sleiti, Al-Ammari & Musharavati (2024)** — *Novel integrated system for power, hydrogen, and ammonia production using direct oxy-combustion sCO2 power cycle with automatic CO2 capture, water electrolyzer, and Haber-Bosch process*. *Energy*, `10.1016/j.energy.2024.132554` (CITED 19); preprint `10.2139/ssrn.4471730`. `[title-only]` — polygeneration, not a renewables-driven NH₃ sizing study.

## A2. Power-to-ammonia dispatch, scheduling, optimisation, MILP — 7 works

1. **Cheng & Ji (2026)** — *Optimal Scheduling of Weak-Grid Green Ammonia Systems Based on ALK–PEM Electrolyzer Coordination*. *Energies*, `10.3390/en19122807`. **The single most on-point dispatch paper in the corpus.** MILP, 15-min resolution over a two-day horizon, integrating "renewable power supply, grid electricity purchase, electrolysis, hydrogen storage, and **flexible ammonia synthesis** in a unified framework", with explicit off / hot-standby / running states **for the electrolysers**. Reports curtailment ratio and grid-purchase share. Notably, it does **not** report a minimum load, ramp rate, or min-up/down time for the ammonia synthesis unit (see Part C).
2. **Pistolesi, Facchino, Bassano & Giaconia (2026)** — *Quantifying the role of process flexibility in power-to-ammonia: Hierarchical rule-based scheduling for dispatch optimization and plant sizing*. *IJHE*, `10.1016/j.ijhydene.2026.155281`. `[title-only]` — **highest-priority full-text retrieval target**: the title places it at the exact intersection of flexibility quantification, dispatch and sizing, and the method is **rule-based, not MILP**.
3. **He, Zhao, Tan & Jing (2026)** — *Optimal Dispatch of Offshore Wind-Hydrogen-Ammonia System Considering Three-tier Ammonia Reserve Mechanism*. ACPEE, `10.1109/acpee69242.2026.11524780`. `[title-only]`
4. **Li, Li, Yang & Zhang (2026)** — *Optimal Scheduling of Off-Grid Wind-Solar-Hydrogen-Ammonia Integrated System Considering Coordination of Electrolyzer and Energy Storage*. Springer LNEE, `10.1007/978-981-95-6841-3_8`. `[title-only]`
5. **Gu, Li & Ning (2024)** — *Optimal Planning of Zero-Carbon Off-Grid Ammonia-Hydrogen-Based Microgrids Considering Hybrid Types of Electrolyzer Modules*. PSGEC, `10.1109/psgec62376.2024.10721092`. `[title-only]` — title indicates heterogeneous electrolyser *modules* inside an NH₃ planning model.
6. **Yao, Zhang, Deng & Xu (2025)** — *Intelligent Optimization of On/Off Grid Wind Solar Hydrogen Synthesis Green Ammonia System Based on Big Data Analysis*. ISPM2025, `10.52202/081497-0108`. `[title-only]` — **the only China-specific green-ammonia optimisation hit in the whole corpus.**
7. **Wang, Wang, Li & Zhao (2026)** — *Integrated Configuration and Dispatch Optimization for Standalone Wind–Solar–Hydrogen-to-Methanol Systems with Maintenance-Aware Thermal-Ready Methanol Synthesis*. NESP, `10.1109/nesp70395.2026.11622181`. `[title-only]` — methanol analogue; relevant as a **structural** precedent ("Thermal-Ready" = synthesis unit kept hot), not as ammonia literature.

## A3. Haber-Bosch loop dynamics, flexibility, min load, ramp, control, MPC — 12 works

1. **Rosbo, Jensen, Skogestad & Jørgensen (2025 preprint; 2026 journal)** — *Optimisation and robust control of a load-flexible Haber–Bosch ammonia synthesis loop*. SSRN `10.2139/ssrn.5379004`; *Computers & Chemical Engineering* `10.1016/j.compchemeng.2026.109614` (CITED 5). `[title-only]` — **the most directly targeted work in the corpus**; abstract absence is a major retrieval gap.
2. **Fahr, Kender, Bohn & Rehfeldt (2025)** — *Dynamic simulation of a highly load-flexible Haber–Bosch plant*. *IJHE*, `10.1016/j.ijhydene.2025.01.039` (CITED 26). `[title-only]` — simulation, not optimisation (per title).
3. **Verleysen, Parente & Contino (2021)** — *How sensitive is a dynamic ammonia synthesis process? Global sensitivity analysis of a dynamic Haber-Bosch process (for flexible seasonal energy storage)*. *Energy*, `10.1016/j.energy.2021.121016` (CITED 63). `[title-only]` — GSA of a dynamic HB model.
4. **Verleysen, Parente & Contino (2023)** — *How does a resilient, flexible ammonia process look? Robust design optimization of a Haber-Bosch process with optimal dynamic control powered by wind*. *Proceedings of the Combustion Institute*, `10.1016/j.proci.2022.06.027` (CITED 29). `[title-only]` — robust design optimisation with dynamic control.
5. **Kong, Zhang & Daoutidis (2024)** — *Nonlinear model predictive control of flexible ammonia production*. *Control Engineering Practice*, `10.1016/j.conengprac.2024.105946` (CITED 34). `[title-only]`
6. **Cabral, Bagheri & Pourkargar (2024)** — *Learning-based Model Predictive Control of an Ammonia Synthesis Reactor*. ACC, `10.23919/acc60939.2024.10644317` (CITED 1). `[title-only]`
7. **Zhang & Kong (2026)** — *Stochastic Model Predictive Control Strategy for Renewable Energy Hydrogen Production and Ammonia Synthesis System*. CCDC, `10.1109/ccdc69976.2026.11560793`. `[title-only]`
8. **Salmon & Bañares-Alcántara (2023)** — *Impact of process flexibility and imperfect forecasting on the operation and design of Haber–Bosch green ammonia*. *RSC Sustainability*, `10.1039/d3su00067b` (CITED 41). Abstract (2 sentences): "Inability to predict the weather, and to rapidly adjust the operating rate of Haber–Bosch synthesis, are major challenges for green ammonia production. This article assesses and provides methods for managing both challenges." — **the corpus's clearest statement of the forecast-error × ramp-capability coupling, but with zero numbers in the abstract.**
9. **Katjipaha, Basnet, Wendt & Lee (2026)** — *Integrated Design and Optimization Framework for a Traditional Haber–Bosch Plant Toward Cleaner Ammonia Production*. SSRN, `10.2139/ssrn.7331488`. Aspen Plus–Python optimisation of operating pressure across four design pressures with validated kinetics; reports that "intermediate pressures of 180–240 bar generally provide lower electricity consumption per tonne of ammonia". **Loop-design optimisation, not dispatch; no min load or ramp content.**
10. **Spatolisano & Kiss (2026)** — *Process-level energy assessment of sorption-enhanced ammonia separation in distributed Haber–Bosch synthesis*. SSRN, `10.2139/ssrn.6886853`. PSA-based NH₃ separation replacing condensation; quantified recycle-cleanup improvement and the conventional separation energy benchmark of 0.21 kWh/kg NH₃. **Separation/equilibrium-side flexibility enabler; contains no dynamic load-following content.**
11. **Smith & Torrente-Murciano (2021)** — *Exceeding Single-Pass Equilibrium with Integrated Absorption Separation for Ammonia Synthesis Using Renewable Energy—Redefining the Haber-Bosch Loop*. *Advanced Energy Materials*, `10.1002/aenm.202003845` (CITED 98). Recycle-less integrated catalyst–absorbent loop "increasing process agility—adapting to a shifting energy landscape". **Process-chemistry enabler of agility; qualitative on flexibility, no load numbers.**
12. **Torrente-Murciano & Smith (2023)** — *Process challenges of green ammonia production*. *Nature Synthesis*, `10.1038/s44160-023-00339-x` (CITED 35). `[title-only]`

## A4. Electrolyser modelling: modularity, multi-stack, unit commitment, part-load, degradation/cycling — 18 works

1. **Xu, He, Zhang & Wei (2026)** — *Day-ahead optimal scheduling of an integrated wind–solar hydrogen production system with battery and hydrogen storage considering electrolyzer start-up dynamics*. SSRN, `10.2139/ssrn.7197893`. **The corpus's most explicit UC-style electrolyser formulation**: three discrete states (cold/start-up/hot), cold-vs-hot start distinguished "by different start-up durations", and "**minimum continuous operating-time constraints are enforced**", with "Group-level electrolyzer coordination". Reports cost savings. **Downstream is hydrogen demand, not a ramp-limited synthesis loop.**
2. **Qiu, Wen, He & Zhang (2026)** — *Optimal Sizing of Power and Hydrogen Storage Systems Considering Electrolyzer Efficiency and Start-Up Dynamics*. *Energies*, `10.3390/en19071712` (CITED 3). MILP coupling capacity sizing and dispatch with **power-dependent electrolyser efficiency** and start-up dynamics; "Independent control strategies are designed for each electrolyzer". Peak efficiency located at 0.25 p.u. input power, calibrated on industrial test data.
3. **Yu, He & Qian (2026)** — *Day-Ahead Scheduling of Green Hydrogen Production: Coordinating Multi-Electrolyzer System, Shared Auxiliary Units and Battery Energy Storage System*. SSRN, `10.2139/ssrn.7120226`. Multi-electrolyser scheduling capturing **shared lye circulation, multi-state transitions and thermodynamic nonlinearity**; balances utilisation via historical cumulative operating time and explicitly **"reduces thermal-cycling stress"** via BESS. Benchmarks against simple start-stop, cycle rotation, and fast start-stop strategies. **Closest thing in the corpus to a cycling-accounting objective, but for electrolysers only.**
4. **Wu, Zhao & Chen (2026)** — *A hierarchical scheduling framework for optimal dispatch of AEL-PEM hybrid electrolyzer arrays*. *J. Phys. Conf. Ser.*, `10.1088/1742-6596/3218/1/012029`. Moving-average envelope decomposition sends low-frequency power to AEL and high-frequency residuals to PEM, explicitly to "**mitigate the degradation risk associated with AEL load cycling**"; uses "convex hull linearization … with binary variables".
5. **Travaglini, Xevgenos & Bruninx (2026)** — *Green hydrogen integration in refineries: optimizing multi-stack electrolyzer and steam-methane reformer operation under renewable intermittency and market exposure*. SSRN, `10.2139/ssrn.7135493`. **The most sophisticated multi-stack formulation in the corpus**: "component-level electrolyzer representation, explicitly modeling **multi-stack modularity**, variable efficiency, degradation dynamics, and operational state transitions", enabling "joint optimization of internal stack scheduling and system-level dispatch, capturing **asymmetric module behavior**". Downstream is an existing SMR under "strict demand constraints" — not a ramp-limited ammonia loop.
6. **Guan, Zhou, Gu & Liu (2026)** — *Region-Driven Two-Layer Refined Scheduling for Multi-Stack-Integrated Alkaline Electrolyzer in Wind-Hydrogen System*. *IEEE Trans. Smart Grid*, `10.1109/tsg.2026.3668984` (CITED 13). `[title-only]` — multi-stack AEL, two-layer refined scheduling.
7. **Qi, Gong, Zhang & Yang (2026)** — *Power allocation strategy of multi-stack PEM electrolyzer for photovoltaic-hydrogen system considering the degradation of components in the electrolyzer*. *EPSR*, `10.1016/j.epsr.2025.112653` (CITED 2). `[title-only]`
8. **Luxa, Jöres, Yáñez & Souza (2022)** — *Multilinear Modeling and Simulation of a Multi-stack PEM Electrolyzer with Degradation for Control Concept Comparison*. SIMULTECH, `10.5220/0011263300003274` (CITED 10). `[title-only]` — degradation-aware multi-stack model for control comparison.
9. **Li, Fang, Li & Sun (2022)** — *Multi-unit Control Strategy of Electrolyzer Considering Start-Stop Times*. ICPET, `10.1109/icpet55165.2022.9918380` (CITED 4). `[title-only]` — **start-stop minimisation in a multi-unit electrolyser control context.**
10. **Wang, Niu & Zhang (2026)** — *Research on Integrated Energy System Optimal Operation Considering Electrolyzer Dynamic Operation and Lifetime Degradation*. *Sustainability*, `10.3390/su18073423`. MILP over ALK and PEM electrolysers with start–stop and lifetime-degradation modelling; the objective explicitly targets "**increase the proportion of stable operation time**" and "**decrease the number of startups and shutdowns**", extending PEM lifetime by 12.17%. **The clearest precedent in the corpus for treating switching counts and stable-operation share as modelled, reported quantities — but for electrolysers, not ammonia.**
11. **Xu, Ma, Wu & Wang (2024)** — *Degradation prediction of PEM water electrolyzer under constant and start-stop loads based on CNN-LSTM*. *Energy and AI*, `10.1016/j.egyai.2024.100420` (CITED 61); preprint `10.2139/ssrn.4858254`. `[title-only]` — data-driven degradation under start-stop.
12. **Shi, Pan, Li & Wang (2026)** — *Capacity configuration and optimization of an off-grid wind-solar-hydrogen integrated system considering hybrid hydrogen production with alkaline electrolyzers and proton exchange membrane electrolyzers*. *Renewable Energy*, `10.1016/j.renene.2025.124814` (CITED 7). `[title-only]`
13. **Huang, Zhang, Ge & He (2023)** — *Day-ahead optimal scheduling strategy for electrolytic water to hydrogen production in zero-carbon parks type microgrid for optimal utilization of electrolyzer*. *Journal of Energy Storage*, `10.1016/j.est.2023.107653` (CITED 92). `[title-only]`
14. **Liu, Su, Liu & Huang (2024)** — *Optimal scheduling of Wind-Solar-Hydrogen-Storage Integrated Energy System Considering Internal Mechanism of PEM Electrolyzer*. EI2, `10.1109/ei264398.2024.10991930`. `[title-only]`
15. **Xiao, Chen, Tang & Wang (2026)** — *Research on Multi-Objective Capacity Configuration and Electrolyzer Cluster Coordinated Scheduling of Grid-Connected Wind-Solar-Hydrogen Storage System Based on Double-Layer Optimization*. NETPS, `10.1109/netps70564.2026.11650561`. `[title-only]` — "electrolyzer cluster" = modular fleet.
16. **Sun, Zhao, Sun & Liang (2025)** — *Optimal sizing and dynamic dispatch of hybrid electrolyzer for industrial-scale renewable hydrogen integration*. SSRN, `10.2139/ssrn.5592993`. `[title-only]`
17. **Altinpulluk & Yildirim (2026)** — *Robust condition-based generation maintenance: Balancing operations and start/stop cycling to control asset degradation rates*. *Reliability Engineering & System Safety*, `10.1016/j.ress.2025.111776`. `[title-only]` — generation assets, but the **operations-vs-cycling trade-off framing is methodologically transferable**.
18. **Arsalis, Papanastasiou & Georghiou (2025)** — *Lifetime Performance Degradation of an Anion Exchange Membrane Electrolyzer Under Dynamic Operation in a Photovoltaic-Powered Nanogrid Environment*. SSRN, `10.2139/ssrn.5333294`. `[title-only]`

## A5. Hydrogen storage buffering / sizing / state-of-charge management — 6 works (+2 cross-listed)

1. **Isella & Manca (2025)** — *A general criterion for the design and operation of flexible hydrogen storage in Power-to-X processes*. *IJHE*, `10.1016/j.ijhydene.2024.12.228` (CITED 14). `[title-only]` — **the title claims exactly a general design/operation criterion for the H₂ buffer. Highest-value retrieval target for the buffering thread.**
2. **Mucci, Mitsos & Bongartz (2023)** — *Cost-optimal Power-to-Methanol: Flexible operation or intermediate storage?* *Journal of Energy Storage*, `10.1016/j.est.2023.108614` (CITED 75). `[title-only]` — **the corpus's canonical statement of the flexibility-versus-storage trade-off**, for methanol.
3. **Franco, Carcasci, Ademollo & Calabrese (2025)** — *Integrated Plant Design for Green Hydrogen Production and Power Generation in Photovoltaic Systems: Balancing Electrolyzer Sizing and Storage*. *Hydrogen*, `10.3390/hydrogen6010007` (CITED 17). Quantifies the electrolyser-downsizing vs storage-expansion trade and reports diminishing returns on added storage.
4. **Mehr & Carton (2025)** — *Techno-Economic Analysis of Green Hydrogen Storage in Salt Caverns: Evaluating Cycling Effects and Cavern Scaling on the Levelized Cost of Hydrogen Storage…*. SSRN, `10.2139/ssrn.5129869`. `[title-only]` — **cycling effects priced into storage cost.**
5. **Su, Li, Wang & Zheng (2023)** — *Operating characteristics analysis and capacity configuration optimization of wind-solar-hydrogen hybrid multi-energy complementary system*. *Frontiers in Energy Research*, `10.3389/fenrg.2023.1305492` (CITED 9). Hybrid energy-storage module with a moving-average smoothing strategy; reports volatility reduction, IRR, and annual coordination/cycle proportions.
6. **Zhao, Zhao, Cao & Zhu (2025)** — *Capacity configuration and control optimization of off-grid wind solar hydrogen storage system*. *Energy*, `10.1016/j.energy.2025.136002` (CITED 18); preprint `10.2139/ssrn.5049417`. `[title-only]`
7. *(cross-listed A4)* **Qiu et al. (2026)** — hydrogen storage tank sizing as an optimisation output (3500 kg).
8. *(cross-listed A4)* **Shi et al. (2026)** — ALK/PEM hybrid H₂ system sizing.

## A6. Grid interaction, curtailment, electricity market, capacity charges — 3 works (+1 cross-listed)

> **This bucket is nearly empty. The dedicated query for it (q09) produced zero abstracts about green ammonia and grid interaction.** The only relevance signal in q09 is a title with no abstract.

1. **Anon. (2022)** — *Sector Coupling of Green Ammonia Production to Australia's Electricity Grid*. In *Computer Aided Chemical Engineering (PSE 2022)*, `10.1016/b978-0-323-85159-6.50317-1` (CITED 4). `[title-only]` — **the single entry in the entire corpus whose title names the exact A6 topic.**
2. **Lauro, Têtu & Geman (2024)** — *Green Ammonia Production in Stochastic Power Markets*. *Commodities*, `10.3390/commodities3010007` (CITED 5); preprint `10.20944/preprints202402.0778.v1`; earlier SSRN `10.2139/ssrn.4601591`. Optimises ammonia production across electricity-procurement types under stochastic power **and** ammonia prices; the stated contribution is that "**This study shows the pivotal role of flexibility** when dealing with fluctuating renewable production and volatile electricity prices to maximise profits and better manage risks." No numbers in the abstract.
3. **Voulkopoulos, Dimitriadis & Georgiadis (2024)** — *Optimal scheduling of a RES – Electrolyzer aggregator in electricity, hydrogen and green certificates markets*. *IJHE*, `10.1016/j.ijhydene.2024.06.379` (CITED 38). `[title-only]` — multi-market participation, electrolyser aggregator (not ammonia).
4. *(cross-listed A2)* **Cheng & Ji (2026)** — "weak-grid" operation, explicitly reports "grid electricity share" and "curtailment ratio".

## A7. Metrics / indicators / stability / flexibility assessment methodology — 15 works

1. **Lu, Li, Qiao & Xie (2024)** — *Flexibility assessment based on operational simulation*. In *Power System Flexibility*, `10.1016/b978-0-323-99517-7.00008-7`. `[title-only]` — **canonical flexibility-assessment-by-simulation reference.**
2. **Akbari, Lopes & Martins (2024)** — *The potential of residential load flexibility: An approach for assessing operational flexibility*. *IJEPES*, `10.1016/j.ijepes.2024.109918` (CITED 15); preprint `10.2139/ssrn.4527303`. `[title-only]` — an *operational* flexibility assessment method (demand-side).
3. **Dang, Niu, Fan & Du (2026)** — *Enhancing operational flexibility and stability of coal-fired units under wide-load conditions: A thermo-chemical frequency-based modeling and control strategy*. *Energy*, `10.1016/j.energy.2026.141562`. `[title-only]` — **the only title in the corpus that pairs "operational flexibility" with "stability" for a wide-load dispatchable unit; a strong structural analogue for a flexible HB loop.**
4. **Jiang, Xu, Shen & Feng (2025)** — *Operational Flexibility Assessment of a Power System Considering Uncertainty of Flexible Resources Supported by Wind Turbines Under Load Shedding Operation*. *Processes*, `10.3390/pr13113635`. Probabilistic flexibility assessment coupling a flexibility-supply control model, nonparametric kernel-density wind model, and Monte Carlo sampling; conclusion is that the resource "**cannot provide stable bi-directional regulation capabilities**". **A concrete precedent for formally assessing a flexibility/stability property with uncertainty propagation.**
5. **Fariña-González, García-Afonso & Delgado-Torres (2026)** — *Base load vs. Flexibility: Operational Challenges of Geothermal Integration in Constrained Power Systems*. SSRN, `10.2139/ssrn.7038286`. Calibrated MILP Unit-Commitment model validated against actual dispatch; finds that capturing the benefit "requires deviating from traditional base load operation" and that flexible operation imposes "**capacity factor penalties that challenge the plant's economic viability**", while "prioritizing rigid geothermal load deteriorates system performance". **The closest methodological template in the corpus for pricing a base-load-vs-flexibility trade-off inside a MILP UC framework** (different asset class).
6. **Du & Sun (2026)** — *Risk Assessment of Grid-Integrated Energy Service Projects: A Hybrid Indicator-Based Fuzzy-Entropy-BP Evaluation Framework*. *Sustainability*, `10.3390/su18021002` (CITED 1). A **30-indicator** system with entropy–BP weighting, whose weights are "confirmed through **robustness tests based on indicator removal and data perturbation**". **The corpus's best single piece of evidence for indicator-set robustness testing (indicator ablation) — but no redundancy formalism, no incremental-information test, no preregistration, and not operational stability.**
7. **Li (2026)** — *A protocol-sensitivity indicator framework for reusable sustainability evidence tables*. SSRN, `10.2139/ssrn.6517459`. Benchmarks **eight plausible protocols** across six evidence tables; "Across **27 benchmark-model combinations, protocol choice changed implied percent effects by a median of 11.7 percentage points** and, in the nitrification-inhibitor ammonia benchmark, **reversed the direction of the inferred effect**"; concludes "protocol choice is not a minor technical detail but **a measurable source of indicator instability**", and proposes a reporting panel recording "split design, weighting, missing-data policy, feasible protocol set, and headline-range outputs". **This is the strongest available precedent for treating analytical-protocol choice itself as a measurable robustness axis — the intellectual ancestor of a "protocol-locked" indicator selection, but in environmental evidence synthesis, not energy operations.**
8. **Dağılgan & Ercan (2025)** — *Developing a Sustainability Reporting Framework for Construction Companies: Prioritization of Themes with Delphi Study Approach*. *Sustainability*, `10.3390/su17073014` (CITED 7). Uses "**the Delphi analysis technique**" to judge "the materiality and **validity** of sustainability themes", reporting "an **acceptable consistency ratio**" and converging on "a total of **twenty-six themes**". **The corpus's only example of a formal, staged, expert-consensus-locked selection-and-pruning procedure.**
9. **Aslantas & Kutlu Gündoğdu (2026)** — *Enhancing Sustainable Traffic Safety Through Machine Learning: A Risk Assessment and Feature Selection Framework Using NGSIM Data*. *Sustainability*, `10.3390/su18052423` (CITED 1). Builds a risk score from "**five key risk indicators**" using "**Spearman's rho coefficient weights**", then performs formal feature selection yielding "**26 key driving behavior features**" that predict the score "with over **85% accuracy**", plus feature-importance analysis. **A concrete precedent for formal quantitative indicator/feature selection and importance ranking (non-energy).**
10. **Valizadeh & Hayati (2025)** — *Formulating indicator selection and composite index validation and application system for agricultural sustainability assessment*. *Results in Engineering*, `10.1016/j.rineng.2025.106978` (CITED 10). `[title-only]` — **title explicitly promises "indicator selection" plus "composite index validation"; high-value retrieval target for the indicator-selection thread.**
11. **Cucchiella, Rotilio, Ehtsham & Marchionni (2026)** — *Artificial Land as a Candidate Indicator of Structural Territorial Constraint: A Parsimonious Framework for Regional Sustainability Assessment in Italy*. *Sustainability*, `10.3390/su18178739`. Proposes a deliberately **parsimonious** single-indicator framework; explicitly concedes that "its **convergent validity** against high-resolution spatial datasets … **remains to be formally tested in future empirical research**". **Direct evidence that the corpus's indicator literature uses validity vocabulary but leaves validity unverified.**
12. **Anon. (2022)** — *Dynamic Operability Analysis for the Calculation of Transient Output Constraints of Linear Time-Invariant Systems*. In *Computer Aided Chemical Engineering (PSE 2022)*, `10.1016/b978-0-323-85159-6.50059-2`. `[title-only]` — **the only "operability" hit of substance in the corpus: operability expressed as transient output constraints. Directly relevant conceptual anchor.**
13. **Anon. (2022)** — *Driving force constraints and physical and/or chemical equilibrium conditions*. In *Synthesis and Operability Strategies for Computer-Aided Modular Process Intensification*, `10.1016/b978-0-32-385587-7.00029-4`. `[title-only]` — operability framing for process intensification.
14. **Peters, Alobaid & Epple (2020)** — *Operational Flexibility of a CFB Furnace during Fast Load Change—Experimental Measurements and Dynamic Model*. *Applied Sciences*, `10.3390/app10175972` (CITED 31). Load-following experiments from 60% to 100% load with **4 load changes**, plus a validated dynamic model; notes hysteresis-like asymmetry because "the hydrodynamic condition after a load change depends on if the load change was in positive or negative direction". **The corpus's only worked example of quantifying load-following flexibility of a continuous thermal process — the closest structural analogue to a ramping HB loop.**
15. **Mohammadi, Norouzi & Saif (2025)** — *Impact Assessment of Optimally-Allocated Distributed Generation Units in Active Distribution Networks on Operational Flexibility and Stability*. NAPS, `10.1109/naps66256.2025.11272415`. `[title-only]`

## A8. Reviews and roadmaps — 11 works

1. **Ye & Tsang (2023)** — *Prospects and challenges of green ammonia synthesis*. *Nature Synthesis*, `10.1038/s44160-023-00321-7` (**CITED 328**). `[title-only]`
2. **Humphreys & Tao (2024)** — *Advancements in Green Ammonia Production and Utilisation Technologies*. *Johnson Matthey Technology Review*, `10.1595/205651324x16946999404542` (CITED 17). Narrative overview spanning electrochemical routes, renewable-powered Haber–Bosch, combustion, fuel cells and cracking; **no quantitative flexibility metrics in the abstract.**
3. **Khan & Majeed (2026)** — *Green ammonia as a hydrogen carrier: Advances in production, storage, cracking, utilization, and techno-economic analysis*. *RSER*, `10.1016/j.rser.2026.117290`. `[title-only]`
4. **Gezerman (2022)** — *A Critical Assessment of Green Ammonia Production and Ammonia Production Technologies*. *Kemija u industriji*, `10.15255/kui.2021.013` (CITED 8). `[title-only]`
5. **Ince, Colpan, Serincan & Pasaogullari (2024)** — *Hydrogen Utilization for Renewable Ammonia Production (Power-to-Ammonia)*. Book chapter, `10.1201/9781032656212-11`. `[title-only]`
6–11. **Edited book *Techno-Economic Challenges of Green Ammonia as an Energy Vector* (2021)**, `10.1016/c2019-0-01417-3` (CITED 7), and its chapters: *Pathways for Green Ammonia* (`10.1016/b978-0-12-820560-0.00003-5`); *Ammonia Production Technologies* (`10.1016/b978-0-12-820560-0.00004-7`, CITED 79); *Use of Ammonia for Heat, Power and Propulsion* (`10.1016/b978-0-12-820560-0.00006-0`); *Techno-Economic Aspects of Production, Storage and Distribution of Ammonia* (`10.1016/b978-0-12-820560-0.00008-4`, CITED 23); *Techno-Economic Aspects of the Use of Ammonia as Energy Vector* (`10.1016/b978-0-12-820560-0.00009-6`). All `[title-only]`.

---

## Papers judged IRRELEVANT and dropped

### (i) Crossref editorial artifacts (not papers) — dropped without assessment
Peer-review reports, decision letters and author responses attached to real papers; plus 4 grant records and 3 book front-matter/copyright/acknowledgement records.

- Attached to Salmon & Bañares-Alcántara 2023: `10.1039/d3su00067b/v2/review2`, `/v2/review1`, `/v1/review1`, `/v3/review1`, `/v1/review2`, `/v1/decision1`, `/v2/decision1`, `/v3/decision1`, `/v2/response1`, `/v3/response1` (10)
- Attached to Rosa & Tonelli, *Optimal design of decentralized ammonia production via electric Haber–Bosch*: `10.1039/d5gc06782k/v1/review1`, `/v2/review1`, `/v1/review2`, `/v1/decision1`, `/v2/decision1`, `/v2/response1` (6)
- Attached to *Haber–Bosch 2.0 for low-carbon ammonia production*: `10.1039/d6ee01125j/v2/review2`, `/v1/review3`, `/v1/review2`, `/v1/review1`, `/v2/review1` (5)
- Attached to *An efficient solution method for integrated unit commitment and natural gas network operational scheduling…*: `10.1002/2050-7038.12662/v2/review4`, `/v1/review3`, `/v2/review3`, `/v3/review4`, `/v4/review1`, `/v2/review1` (6)
- Attached to *Multi-objective unit and load commitment in smart homes*: `10.1002/2050-7038.12614/v1/review1`, `/v2/review1`, `/v1/review3` (3)
- Attached to *Counting the lifetime cost of obesity*: `10.1111/dom.15447/v1/review2`, `/v2/review1`, `/v1/review1`, `/v2/decision1`, `/v1/decision1` (5)
- Attached to *Progress and prospects in electrocatalytic ammonia synthesis reactors*: `10.1039/d6cc00296j/v2/review1`, `/v1/review1` (2)
- *eLife* assessments (archaeal membranes, olfactory memory): `10.7554/elife.105432.1.sa3`, `.3.sa0`, `.2.sa3`, `10.7554/elife.104443.1.sa3`, `.2.sa4`, `.3.sa0`, `10.7554/elife.107905.2.sa3`, `.1.sa3`, `.3.sa0`, `10.7554/elife.100932.3.sa0`, `.2.sa3`, `.1.sa3` (12)
- Grants / front matter: `10.3030/884229`, `10.3030/864537`, `10.3030/951880`, `10.54499/2025.05272.bdana`; `10.1016/b978-0-12-820560-0.12001-6`, `.04001-7`, `.01001-8`

### (ii) Wrong domain — dropped (DOIs given)
- **EV / transport / buildings / data centres:** `10.1007/978-981-97-0312-8_8`, `10.1007/978-981-97-0312-8_2`, `10.1007/978-981-97-0312-8_4`, `10.1016/j.renene.2025.123073`, `10.2139/ssrn.7152479`, `10.1016/j.est.2026.121551`, `10.1016/j.trc.2024.104656`, `10.1201/9781003277231-2`
- **Generic control/MPC theory, unrelated plant:** `10.1109/cdc42340.2020.9303936`, `10.1109/cdc42340.2020.9304200`, `10.1002/9781394442294.ch14`, `10.23919/ccc58697.2023.10240118`, `10.1201/9781003773719-3`, `10.23919/ecc51009.2020.9143615`, `10.36227/techrxiv.175289447.77646909/v1`, `10.1115/icone31-136137` (HTGR nuclear load following — **relevant only as an external analogy, no ammonia content**)
- **Other power-system assets (geothermal, CSP, hydro, biomass, coal, nuclear, V2G, DG):** `10.2139/ssrn.7038286` *(retained in A7 for method)*, `10.2139/ssrn.4358467`, `10.1016/j.renene.2023.119513`, `10.1016/j.tia.2022.3217229`, `10.1109/icmnwc56175.2022.10031916`, `10.1016/j.est.2022.104282`, `10.2172/1970242`, `10.3390/electronics11010109`, `10.1016/j.renene.2022.05.106`, `10.1109/sges70879.2026.11662601`, `10.1109/epee67527.2025.11428500`, `10.1109/icesep70386.2026.11607967`, `10.21203/rs.3.rs-1827606/v1`, `10.46855/energy-proceedings-11474`, `10.1109/naps66256.2025.11272415` *(listed A7)*, `10.1109/sgai64825.2025.11009756`
- **Power economics / law / tariffs with no ammonia link:** `10.5771/9783748913627` and its 15 chapter DOIs (`-1`, `-13`, `-15`, `-17`, `-20`, `-39`, `-56`, `-81`, `-88`, `-110`, `-127`, `-133`, `-141`, `-146`, `-161`), `10.2139/ssrn.4343013`, `10.1109/icsgsc62639.2024.10813859`, `10.2139/ssrn.6678966`, `10.64628/aai.ksjdd7du9`, `10.47191/ijcsrr/v9-i7-21`, `10.1063/9780735423152_002`, `10.1016/j.renene.2024.119940`, `10.2139/ssrn.5292461`
- **H₂/PtX but neither ammonia nor buffer/stack scheduling:** `10.1109/icips59254.2023.10404440`, `10.1016/j.ijhydene.2025.05.329`, `10.1016/j.est.2021.103745`, `10.1109/iceeps70377.2026.11662684`, `10.2139/ssrn.5736170`, `10.2139/ssrn.5616732`, `10.1016/j.est.2024.115171`, `10.1016/j.energy.2022.124583`, `10.2139/ssrn.6022264`, `10.2139/ssrn.4141408`, `10.2139/ssrn.5107161`, `10.2139/ssrn.5592993` *(listed A4)*, `10.2139/ssrn.5049417` *(listed A5)*, `10.1016/j.energy.2022.124046`, `10.2139/ssrn.5116971`, `10.1016/j.energy.2025.139497`, `10.2139/ssrn.4417028`, `10.2139/ssrn.4739203`, `10.2139/ssrn.5759779`, `10.2139/ssrn.4946852`, `10.1109/icepet61938.2024.10626286`, `10.1109/ceepe62022.2024.10586445`, `10.1109/ictis60134.2023.10243833`, `10.1016/j.cherd.2026.08.022`
- **Batteries / fuel cells / materials:** `10.2139/ssrn.4238410`, `10.1109/vppc63154.2024.10755359`, `10.1016/j.ijhydene.2021.05.010`, `10.2139/ssrn.5333294` *(listed A4)*, `10.3390/ma19173712`
- **Ammonia but non-energy-technology:** `10.1016/j.biotechadv.2026.108898` (microbial electrosynthesis), `10.1007/3-030-35106-9_5` (ammonia cracking for fuel cells), `10.1007/978-981-97-0507-8_6` (NH₃ in IC engines), `10.1596/41670` (biomass/ammonia co-firing in coal plants), `10.1007/978-981-19-4767-4_16` (NH₃ production system overview)
- **q13 query noise (off-topic, wrong field entirely):** `10.53040/cga11.2021.101`, `.098`, `.145`, `.099`, `.100`, `.072`, `10.31254/jmr.2021.7105`, `10.52547/crpase.7.2.2334`, `10.47056/1814-3490-2022-4-269-276`, `10.15376/biores.21.2.2878-2891`, `10.47056/0365-9615-2025-180-9-338-344`, `10.18240/ijo.2021.07.04`, `10.26420/austinsurgcasereport.2023.1060`, `10.7934/p3570`, `10.52768/casereports/1009`
- **q15 noise:** `10.21203/rs.3.rs-9888304/v1` (KRAS G12C covalent inhibitors)
- **Two "oxy-combustion oxygen production" / "PV-hydrogen power" abstracts with numbers but no ammonia or ammonia-operability content:** `10.21203/rs.3.rs-5166276/v1`, `10.3390/hydrogen6010007` *(retained A5)*

---

# PART B — QUANTITATIVE EXTRACTION TABLE

**Rule applied:** a row exists only if the number physically appears in one of the 15 files. Every figure is quoted verbatim from the source abstract. **No number is inferred, interpolated, or supplied from outside knowledge.** Where a category has no data, the category is declared empty.

## B1. Minimum stable load of Haber-Bosch / ammonia loop

| Value | Context (verbatim fragment) | Source |
|---|---|---|
| **20%** | "a **flexibility factor (ratio between the minimum operating capacity and the nominal capacity of the plant) of 20%** offers the most cost-effective solution, but production is scaled down to 64 tpd" | Pistolesi, Giaconia, Bassano & De Falco (2025), *Fuels*, `10.3390/fuels6020039` |
| — | No other paper in the corpus states a minimum stable load for the ammonia loop. The phrase **"minimum load" does not appear anywhere in the 15 files** (verified by full-corpus search). | — |

## B2. Ramp rates of the ammonia loop (%/h)

| Value | Source |
|---|---|
| **No data.** The terms **"ramp" and "ramping" return zero matches across all 15 files** (verified by full-corpus search). No paper in this corpus reports an ammonia-loop ramp rate in %/h. | — |

Related but *not* a ramp rate: Peters et al. (2020) describe a coal-fired CFB combustor taken through "transient operation from **60% to 100% load**" with "**4 load changes**" (`10.3390/app10175972`) — a different asset class.

## B3. Start-up / shutdown times, minimum up/down times

| Value | Verbatim fragment | Source |
|---|---|---|
| 3 discrete states | "Electrolyzer operation is represented by **three discrete states, namely cold, start-up, and hot states**." | Xu, He, Zhang & Wei (2026), SSRN `10.2139/ssrn.7197893` |
| cold vs hot start differ | "**Cold-start and hot-start processes are distinguished by different start-up durations**, and **minimum continuous operating-time constraints are enforced** to reflect practical operation." (no numeric duration given) | same |
| 3 states (ALK/PEM) | "The **off, hot-standby, and running states** of ALK and PEM electrolyzers are explicitly represented." | Cheng & Ji (2026), *Energies*, `10.3390/en19122807` |
| — | "minimum up/down time" / "min up" / "min down" return **zero matches** across all 15 files. | — |

## B4. LCOA values

| Value | Verbatim fragment | Source |
|---|---|---|
| **AU$756/t (2025); AU$659/t (2030)** | "a **levelised cost of ammonia (LCOA) of AU$756/tonne and AU$659/tonne in 2025 and 2030**, respectively" | Wang, Walsh, Longden & Palmer (2022/2023), `10.31223/x5vp9g` / `10.1016/j.enconman.2023.116790` |
| gas-price thresholds | "given a feedstock natural gas price higher than **AU$14/MBtu**"; "assuming a lower gas price of **AU$6/MBtu**, a carbon price would need to be in place of at least **AU$123/tonne**" | same |
| **103.79 USD/t** | "can achieve an **LCOA of 103.79 USD/ton**" | Jahanbakhsh (2025), SSRN `10.2139/ssrn.5166467` |
| **≈0.59 USD/kg NH₃ (2050)** | "the optimal LCOA for a green ammonia production is approximately **0.59 USD/kgNH3 in 2050**" | Pistolesi et al. (2025), `10.3390/fuels6020039` |
| carbon allowance | "provided that a carbon emission allowance of **USD 0.12/kgCO2** is applied" | same |
| **US$153–197/t NH₃ (energy cost)** | "energy costs per tonne of NH₃ … **U.S.$195, 197, 158, and 179 per tonne of NH₃**"; CLAS alternative "**U.S.$153 per tonne of NH₃**" | Pfromm & Aframehr (2022), `10.1063/5.0101709` |
| boundary conditions | "A renewable electricity price of **U.S.$0.02 per kWhelectric**, and **U.S.$6 per 106 BTU** for natural gas is assumed." — quoted exactly as it appears; the file has flattened the superscripts (`kWh_electric`, `10⁶ BTU` in the original) | same |
| scale | "a Haber–Bosch (H–B) synthesis loop is available to produce **1000 metric tons (tonnes) of renewable NH₃ per day**" | same |
| **€6/kg H₂ (LCOH)** | "Cost analysis estimates a **Levelized Cost of Hydrogen (LCOH) as low as €6/kg** with an optimized configuration of a **2 MW electrolyzer and 2 MWh battery**." | Franco, Carcasci, Ademollo & Calabrese (2025), `10.3390/hydrogen6010007` |
| — | Note: `AU$` values are **Australian dollars**, not USD. Any comparison against the USD figures requires an FX assumption this corpus does not provide. | — |

## B5. Electrolyser minimum load, efficiency, kWh/kg or kWh/Nm³

| Value | Verbatim fragment | Source |
|---|---|---|
| **peak efficiency at 0.25 p.u.** | "The **electrolyzer efficiency peak at 0.25 p.u. input power** is calibrated by industrial test data, and the optimization results show strong robustness to the slight deviation of this peak point." | Qiu, Wen, He & Zhang (2026), *Energies*, `10.3390/en19071712` |
| **0.21 kWh/kg NH₃** (separation benchmark) | "benchmarked against the conventional separation requirement of **0.21 kWh kg⁻¹ NH₃**" — this is *ammonia separation* duty, **not** electrolyser specific energy | Spatolisano & Kiss (2026), SSRN `10.2139/ssrn.6886853` |
| electrolyser capacity (kW) | "**145,370 kW of electrolyzer capacity**" | Jahanbakhsh (2025), SSRN `10.2139/ssrn.5166467` |
| electrolyser downsize doubles relative output | "using a **1 MW unit instead of a 2 MW model**, increases operational efficiency by extending nominal power usage, though it reduces total hydrogen output by approximately **50%**" | Franco et al. (2025), `10.3390/hydrogen6010007` |
| PV→H₂ allocation floor | "requiring a **minimum of 50% PV energy allocation** to the hydrogen value chain" | same |
| — | **No electrolyser minimum load (%) and no kWh/Nm³ figure appears anywhere in these 15 files.** No "kWh/Nm³" string exists in the corpus. | — |

## B6. Hydrogen storage durations (hours, days)

| Value | Verbatim fragment | Source |
|---|---|---|
| **237,339 kg H₂** | "**237,339 kg of hydrogen storage capacity** can achieve an LCOA of 103.79 USD/ton" | Jahanbakhsh (2025), SSRN `10.2139/ssrn.5166467` |
| **3500 kg tank** | "a **hydrogen storage tank of 3500 kg**" | Qiu et al. (2026), `10.3390/en19071712` |
| 2-day scheduling horizon (time horizon, not storage duration) | "The model uses a **15 min resolution over a two-day horizon**" | Cheng & Ji (2026), `10.3390/en19122807` |
| — | **No paper states a hydrogen storage duration in hours or days.** Storage appears only as mass (kg) or as a sizing decision variable. | — |

## B7. Curtailment rates, capacity factors

| Value | Verbatim fragment | Source |
|---|---|---|
| **curtailment ratio 3.23%** (high-resource scenario) | "ammonia production reaches **494.93 t**, with a **curtailment ratio of 3.23%** and a **grid electricity share of 0.68%**" | Cheng & Ji (2026), *Energies*, `10.3390/en19122807` |
| grid share **40%** (low-resource) | "ammonia production decreases to **180.09 t** and the **grid electricity share increases to 40%**" | same |
| renewable utilisation **96.7%** | "the optimized system achieves a **renewable energy utilization rate of 96.7%**" | Qiu et al. (2026), `10.3390/en19071712` |
| BESS 7 MWh; tank 3500 kg | "a **BESS capacity of 7 MWh**, and a **hydrogen storage tank of 3500 kg**" | same |
| BESS 6 MWh optimum | "with a **6 MWh BESS** identified as an ideal configuration" | Yu, He & Qian (2026), SSRN `10.2139/ssrn.7120226` |
| 10-min volatility −38.7% | "the **10-min grid-connected volatility is reduced by 38.7%** based on the smoothing strategy" | Su, Li, Wang & Zheng (2023), `10.3389/fenrg.2023.1305492` |
| IRR 13.67% at 0.04 $/kWh | "the internal investment return rate can reach **13.67%** when the electricity price is **0.04 $/kWh**" | same |
| cycle proportion 80.5% / 90% | "the annual coordinated power and cycle proportion of the hybrid energy storage module are **80.5%** and **90%**, respectively" | same |
| grid export peak 3300 kWh | "Surplus energy export to the grid **peaks at 3300 kWh** during periods of high solar generation but is minimal otherwise." | Franco et al. (2025), `10.3390/hydrogen6010007` |
| capacity factor penalty (geothermal, different asset) | "imposing **capacity factor penalties** that challenge the plant's economic viability" | Fariña-González, García-Afonso & Delgado-Torres (2026), SSRN `10.2139/ssrn.7038286` |
| — | **No capacity factor for a wind-PV-ammonia plant appears in the corpus.** "capacity factor" appears only in the geothermal paper above and in an Afghanistan LCOE study (`10.47191/ijcsrr/v9-i7-21`) that has no ammonia content. | — |

## B8. Number of electrolyser stacks / modules

| Value | Verbatim fragment | Source |
|---|---|---|
| multi-stack modularity (no count given) | "component-level electrolyzer representation, explicitly modeling **multi-stack modularity**, variable efficiency, degradation dynamics, and operational state transitions" | Travaglini, Xevgenos & Bruninx (2026), SSRN `10.2139/ssrn.7135493` |
| multi-unit, count unspecified | "**Multi-unit Control Strategy of Electrolyzer** Considering Start-Stop Times" `[title-only]` | Li, Fang, Li & Sun (2022), `10.1109/icpet55165.2022.9918380` |
| "electrolyzer cluster" | "Multi-Objective Capacity Configuration and **Electrolyzer Cluster** Coordinated Scheduling" `[title-only]` | Xiao, Chen, Tang & Wang (2026), `10.1109/netps70564.2026.11650561` |
| multi-stack AEL, count unspecified | "**Multi-Stack-Integrated Alkaline Electrolyzer** in Wind-Hydrogen System" `[title-only]` | Guan, Zhou, Gu & Liu (2026), `10.1109/tsg.2026.3668984` |
| "Group-level electrolyzer coordination" | "**Group-level electrolyzer coordination**, battery storage, hydrogen storage, and time-varying electricity prices are incorporated" | Xu et al. (2026), SSRN `10.2139/ssrn.7197893` |
| — | **No paper in this corpus states a specific number of electrolyser stacks or modules.** The modularity *concept* is present in ≥5 works, but the integer count is never reported in any available abstract. | — |

## B9. Reported cost savings (%) from flexible operation

| Value | Verbatim fragment | Source | Caveat |
|---|---|---|---|
| **−24.96%** electrolyser operating cost | "the optimized schedule reduces **electrolyzer operating cost by 24.96%** and **total electricity-related operating cost by 17.31%** while maintaining stable hydrogen supply" | Xu et al. (2026), SSRN `10.2139/ssrn.7197893` | **Electrolyser/hydrogen system, not ammonia.** Baseline is an incumbent operating strategy, not fixed-load vs flexible. |
| **−17.31%** total electricity-related cost | same | same | same |
| **+2.88% / +3.14% / +2.31%** renewable consumption | "renewable energy consumption rate gains of **2.88%, 3.14%, and 2.31%** over **simple start-stop, cycle rotation, and fast start-stop** strategies" | Yu, He & Qian (2026), SSRN `10.2139/ssrn.7120226` | Multi-electrolyser hydrogen plant; gains are relative to other **electrolyser** scheduling strategies. |
| **↑12.17%** PEM lifetime | "extend the actual lifetime of the PEM electrolyzer by **12.17% versus its rated life**" | Wang, Niu & Zhang (2026), `10.3390/su18073423` | Lifetime extension, not a cost saving; electrolyser only. |
| **−50%** operating cost vs SMR-only | "the hybrid configuration **reduces operational costs by up to 50% compared with the SMR-only baseline**" | Travaglini et al. (2026), SSRN `10.2139/ssrn.7135493` | Hybridisation benefit (electrolyser + SMR), **not** a flexibility benefit. |
| **57%** LCOH swing from remuneration | "variations in the **levelized cost of hydrogen of up to 57%**" | same | Market-design sensitivity, not flexibility. |
| **−41% emissions / −38% cost** | "geothermal integration reduces **emissions and cost by up to 41% and 38%** respectively" | Fariña-González et al. (2026), SSRN `10.2139/ssrn.7038286` | Different asset class (geothermal). |
| **−27.8%** capture cost | "reduces capture costs by approximately **27.8%**" | `10.21203/rs.3.rs-5166276/v1` | Dropped as irrelevant (oxygen production). |

> **Citation-relevant negative finding:** **No paper in this corpus reports a percentage cost saving attributable specifically to making a Haber–Bosch ammonia loop flexible.** Wang et al. state qualitatively that "Flexible operation reduces energy curtailment and leads to lower storage capacity requirements using batteries or hydrogen storage, which would otherwise increase system costs", but give **no percentage**. Pistolesi et al. report LCOA levels under different flexibility factors but **no delta expressed as a % saving**.

## B10. Other quantitative fragments worth recording

| Value | Verbatim fragment | Source | Relevance |
|---|---|---|---|
| HB design pressures 125/180/240/292 bar | "Four design pressures (**125, 180, 240, and 292 bar**) were evaluated using validated ammonia synthesis kinetics" | Katjipaha, Basnet, Wendt & Lee (2026), SSRN `10.2139/ssrn.7331488` | A3 — loop design |
| 180–240 bar favourable | "intermediate pressures of **180–240 bar** generally provide lower electricity consumption per tonne of ammonia while maintaining reasonable reactor bed sizes" | same | A3 |
| HB effluent conditions | "(**220 °C, 150 bar, 24 mol% NH₃**)" | Spatolisano & Kiss (2026), SSRN `10.2139/ssrn.6886853` | A3 |
| condensation <10% per pass | "conventional condensation removes **less than 10% of NH₃ per pass**" | same | A3 |
| recycle cleanup 2.4 → 0.033 mol%, ~70-fold | "The PSA cycle reduced the recycle NH₃ concentration from **2.4 mol% to 0.033 mol%**, corresponding to a **~70-fold improvement** in recycle cleanup." | same | A3 |
| 37 mol% vs 99.99 mol% purity | "the desorption stream contained only **37 mol% NH₃**, significantly below the **99.99 mol% purity** achieved by conventional condensation" | same | A3 |
| catalyst activity <300 °C | "low-temperature (**<300 °C**) activity that quickly approaches equilibrium" | Smith & Torrente-Murciano (2021), `10.1002/aenm.202003845` | A3 |
| Denmark sizing vector | "**212,923 kW** of wind capacity, **85,169 kW** of solar capacity, **145,370 kW** of electrolyzer capacity, **19,096 kWh** of battery storage, and **237,339 kg** of hydrogen storage capacity" | Jahanbakhsh (2025), `10.2139/ssrn.5166467` | A1 |
| 64 tpd production | "production is scaled down to **64 tpd**" | Pistolesi et al. (2025), `10.3390/fuels6020039` | A1 |
| ALK/PEM share shift | "ALK hydrogen production share decreases from **93.96%** … to **75.66%** … while the PEM share increases from **6.04%** to **24.34%**" | Cheng & Ji (2026), `10.3390/en19122807` | A2/A4 |
| 4.2 MW PV case | "hybrid photovoltaic–hydrogen systems integrated with **4.2 MW PV** installations" | Franco et al. (2025), `10.3390/hydrogen6010007` | A5 |
| daily H₂ 26–375 kg | "daily hydrogen production ranging from **26 kg on cloudy winter days to 375 kg** during sunny summer conditions" | same | A5 |
| 5–15 MW geothermal scenarios | "Various deployment scenarios (**5–15 MW**) are analyzed" | Fariña-González et al. (2026), SSRN `10.2139/ssrn.7038286` | A7 |
| 30-indicator system + ablation | "A **30-indicator system** … confirmed through **robustness tests based on indicator removal and data perturbation**" | Du & Sun (2026), `10.3390/su18021002` | **A7 — key for Part C(c)** |
| 26 themes, Delphi, consistency ratio | "a reporting framework was developed consisting of a total of **twenty-six themes**"; "acceptable **consistency ratio**" | Dağılgan & Ercan (2025), `10.3390/su17073014` | **A7 — key for Part C(b)** |
| 8 protocols / 27 combos / 11.7 pp / sign reversal | "We benchmarked **eight plausible protocols across six public evidence tables**" … "Across **27 benchmark-model combinations, protocol choice changed implied percent effects by a median of 11.7 percentage points** and … **reversed the direction of the inferred effect**" | Li (2026), SSRN `10.2139/ssrn.6517459` | **A7 — key for Part C(b),(c)** |
| 5 indicators → 26 features, rho weights, >85% | "**five key risk indicators**"; "**Spearman's rho coefficient weights**"; "**26 key driving behavior features** … with over **85% accuracy**" | Aslantas & Kutlu Gündoğdu (2026), `10.3390/su18052423` | A7 |
| CFB 60→100% load, 4 changes, 1 MWth | "transient operation from **60% to 100% load**"; "**4 load changes**"; "Experiments at **1 MWth scale**" | Peters, Alobaid & Epple (2020), `10.3390/app10175972` | A7 |
| convergent validity untested | "its **convergent validity** … **remains to be formally tested** in future empirical research" | Cucchiella et al. (2026), `10.3390/su18178739` | **A7 — key for Part C(c)** |

---

# PART C — GAP ANALYSIS

## C1. Topics covered densely (a new paper must differentiate against these)

Density below is measured as **number of unique on-topic works**, with the caveat that most are `[title-only]`. A dense topic with only titles means the *topic* is crowded but the *evidence base in this corpus* is thin — so differentiation must be argued against the titles' claims, and full texts are needed.

| Rank | Topic | Works | Why it is crowded |
|---|---|---|---|
| 1 | **Green ammonia LCOA / techno-economic assessment** | ~15 (A1) + 11 reviews (A8) | Every framing of "cost of green ammonia" is already covered: national/site LCOA (Chile, Italy, Denmark, Australia), predictive LCOA surrogates, supply-chain optimisation, energy-cost-only comparisons, and a 2021 edited book. A new LCOA number alone is not publishable. |
| 2 | **Wind–solar–hydrogen capacity configuration / sizing** | ~25 entries in q05 alone | Overwhelmingly Chinese case studies, mostly `[title-only]`, using Kriging/NSGA-III/MCDM/grasshopper/Dirichlet-scenario methods. Methodological novelty in the *sizing algorithm* is exhausted. |
| 3 | **Electrolyser degradation / start-stop / cycling** | ~10 (A4) | Covered from materials (CNN-LSTM degradation prediction), control (multi-unit start-stop minimisation), scheduling (multi-state MILP, min continuous operating time), and economics (lifetime extension %). |
| 4 | **Multi-stack / modular electrolyser scheduling** | ≥5 (A4) | "Multi-stack modularity", "electrolyzer cluster", "multi-unit", "group-level coordination" all already appear, up to `IEEE Trans. Smart Grid` level. |
| 5 | **Generic (non-ammonia) flexibility assessment methodology** | ~8 (A7) | Flexibility assessment by operational simulation, probabilistic flexibility under uncertainty, MILP UC base-load-vs-flexibility trade-offs, load-following flexibility of thermal plant — all occupied, all for *other* assets. |
| 6 | **Power-to-ammonia dispatch/scheduling** | ~7 (A2) | Includes one full MILP abstract (Cheng & Ji 2026) with curtailment and grid-share reporting, plus a rules-based dispatch+sizing paper (Pistolesi 2026). Not yet saturated, but no longer empty. |

**Differentiation implication:** none of the dense topics can carry a Q1 paper on "we did X better". Differentiation must come from *what is not modelled*, not from *which algorithm*.

## C2. Topics that appear rarely or not at all — targeted negative findings

Each sub-question below was tested by reading all 15 files **and** by full-corpus regex search. Where the answer is negative I say so explicitly.

### (a) Do optimisation/dispatch papers report or constrain OPERATIONAL STABILITY / cycling / switching of the AMMONIA SYNTHESIS unit?

**No evidence found in these files.** Precision on what *is* present:

- **Ammonia dispatch with a MILP (Cheng & Ji 2026, `10.3390/en19122807`)** is the closest. It integrates "flexible ammonia synthesis in a unified framework" and references "**continuous ammonia synthesis**", "**maintaining continuous production**", and "**platform-like flexible ammonia operation**". But: (i) the only explicitly modelled discrete states are **electrolyser** states ("The **off, hot-standby, and running states of ALK and PEM electrolyzers** are explicitly represented"); (ii) the abstract reports **no** minimum load, ramp rate, min-up/down time, start count, or switching frequency for the ammonia unit; (iii) no stability *indicator* is reported for the synthesis loop. The word "continuous" is used **qualitatively**.
- **Electrolyser-side cycling/switching is well covered, and only there:**
  - "**minimum continuous operating-time constraints are enforced**" — Xu et al. 2026, `10.2139/ssrn.7197893` (electrolysers).
  - "increase the proportion of **stable operation time** for the electrolyzer, decrease the **number of startups and shutdowns**" — Wang, Niu & Zhang 2026, `10.3390/su18073423` (electrolysers).
  - "**mitigate the degradation risk associated with AEL load cycling**" — Wu, Zhao & Chen 2026, `10.1088/1742-6596/3218/1/012029` (electrolysers).
  - "reduces **thermal-cycling stress**"; benchmarking against "simple start-stop, **cycle rotation**, and fast start-stop" — Yu, He & Qian 2026, `10.2139/ssrn.7120226` (electrolysers).
  - "**Multi-unit Control Strategy of Electrolyzer Considering Start-Stop Times**" `[title-only]` — `10.1109/icpet55165.2022.9918380`.
- **The ammonia-loop dynamic/control literature exists but is not an optimisation-dispatch literature in this corpus**, and its abstracts are absent: Fahr et al. 2025 (`10.1016/j.ijhydene.2025.01.039`, "Dynamic **simulation**"), Verleysen et al. 2021 (GSA) and 2023 (robust design optimisation), Rosbo et al. 2025/2026 ("Optimisation and robust **control**"), Kong et al. 2024 ("Nonlinear **MPC**"), Cabral et al. 2024, Zhang & Kong 2026. **All `[title-only]`** — so I cannot state from these files whether they constrain cycling; I can only state that **no abstract in this corpus shows them doing so**.
- **One candidate where it might occur but is unverifiable:** Pistolesi, Facchino, Bassano & Giaconia (2026), *IJHE*, `10.1016/j.ijhydene.2026.155281` — "Quantifying the role of process flexibility in power-to-ammonia: Hierarchical rule-based scheduling for dispatch optimization and plant sizing". `[title-only]`. **Retrieving this full text is the single highest-value action to close gap (a)/(e).**

**Statement:** No evidence found in these files of any optimisation or dispatch paper that *reports or constrains* operational stability, cycling, or switching of the ammonia synthesis unit. Every instance of such constraints in this corpus applies to **electrolysers**, never to the **ammonia loop**.

### (b) Does any paper perform a formal, preregistered or protocol-locked SELECTION of operational stability indicators?

**No evidence found in these files.** Specifically:

- **The strings "preregist" and "pre-regist" return zero matches across all 15 files.** No paper in this corpus preregisters anything.
- **No paper in this corpus performs indicator selection for operational stability at all**, in any domain. The only indicator-selection work is in unrelated fields.
- **Nearest analogues, and why each falls short:**
  1. **Dağılgan & Ercan (2025), `10.3390/su17073014`** — the corpus's **only** structured, protocol-locked, validity-gated selection procedure: a "**Delphi analysis technique**" applied to judge "the materiality and **validity** of sustainability themes", converging on "**twenty-six themes**" with "an acceptable **consistency ratio**". **Shortfall:** it selects *reporting themes for construction companies*; it is not preregistered (no registration statement appears); and it has no redundancy or incremental-information stage.
  2. **Li (2026), `10.2139/ssrn.6517459`** — the corpus's **only** work treating analytical-protocol choice itself as a measurable variable ("**eight plausible protocols**"; protocol choice moved effects "by a median of **11.7 percentage points**" and "**reversed the direction** of the inferred effect"). **Shortfall:** it measures protocol *sensitivity* in environmental evidence synthesis; it does not *select* indicators and is not preregistered; its "indicator set" (coverage, feasibility, headline swing, sign reversal, decision-translation range) characterises protocol behaviour, not system operability.
  3. **Aslantas & Kutlu Gündoğdu (2026), `10.3390/su18052423`** — a formal quantitative selection funnel (5 risk indicators → risk score → 26 selected features, >85% accuracy, with importance ranking). **Shortfall:** traffic safety; statistical, not protocol-locked or preregistered.
  4. **Valizadeh & Hayati (2025), `10.1016/j.rineng.2025.106978`** — title promises "**indicator selection and composite index validation** and application system". `[title-only]` — **unverifiable; second-most valuable retrieval target for this gap.**

**Statement:** No evidence found in these files of any preregistered or protocol-locked selection of *operational stability indicators*, in power-to-ammonia or in any other energy-system context.

### (c) Does any paper discuss metric REDUNDANCY, metric ROBUSTNESS, or INCREMENTAL INFORMATION among candidate metrics?

**Partial evidence found — but never for operational stability, and never with an incremental-information formalism.**

| Sub-concept | Evidence in these files | Assessment |
|---|---|---|
| **Robustness of an indicator set** | Du & Sun (2026), `10.3390/su18021002`: indicator weights "confirmed through **robustness tests based on indicator removal and data perturbation**" | **Present, and respectable.** Indicator removal is a redundancy *probe* by another name. But no correlation/clustering/VIF analysis, no formal redundancy metric, no incremental-information test; and it concerns risk-assessment indicators for grid-integrated energy service projects. |
| **Redundancy** | The string "redundan" appears **only inside the q11 query header line**, never in any paper title or abstract. | **No evidence found in these files of any explicit redundancy analysis of candidate metrics.** |
| **Incremental information** | The strings "**incremental information**", "**mutual information**", and "**collinear**" return **zero matches** across all 15 files. | **No evidence found in these files.** No paper tests whether a candidate metric adds information beyond metrics already in the set. |
| **Metric importance / ranking** | Aslantas & Kutlu Gündoğdu (2026): Spearman's rho weights; "feature importance analysis reveals that the following distances and inter-vehicle distance variability are particularly effective" | **Present (non-energy).** Importance ranking is not the same as incremental information: importance does not test marginal contribution conditional on the remaining set. |
| **Validity of an indicator** | Cucchiella et al. (2026), `10.3390/su18178739`: "its **convergent validity** against high-resolution spatial datasets … **remains to be formally tested** in future empirical research" | **Validity is named but explicitly left untested** — evidence that the corpus's indicator literature uses validity vocabulary without discharging it. |
| **Protocol/result stability incl. sign reversal** | Li (2026), `10.2139/ssrn.6517459`: median 11.7 pp shift; "**reversed the direction of the inferred effect**" | **The strongest available precedent for robustness-as-sign-stability**, in environmental evidence synthesis. |

**Statement:** No evidence found in these files of any paper that (i) quantifies **redundancy** among candidate metrics, (ii) tests **incremental information** of a candidate metric conditional on others, or (iii) applies any of these gates to **operational stability** metrics for a flexible industrial load. The nearest concepts present are indicator-removal robustness testing (Du & Sun 2026), feature importance (Aslantas 2026), protocol-sensitivity sign reversal (Li 2026), and an explicit admission that convergent validity remains untested (Cucchiella 2026).

### (d) Does any paper integrate a discrete/integer electrolyser module-commitment schedule with a downstream ramp-limited continuous process?

**No evidence found in these files of the complete integration.** The two halves each exist; the junction does not.

**Upstream discrete/integer electrolyser commitment — present, well developed:**
- Travaglini et al. (2026), `10.2139/ssrn.7135493`: "**multi-stack modularity** … **operational state transitions**" with "joint optimization of **internal stack scheduling** and system-level dispatch". **This is the corpus's most advanced integer-module formulation.** Downstream = an existing SMR under "strict demand constraints" (a hydrogen-supply constraint, not a ramp-limited synthesis model).
- Xu et al. (2026), `10.2139/ssrn.7197893`: "three discrete states, namely **cold, start-up, and hot**", "**minimum continuous operating-time constraints**". Downstream = "downstream hydrogen demand" (high/low), i.e. a demand parameter, **not** a ramp-limited process model.
- Wu, Zhao & Chen (2026), `10.1088/1742-6596/3218/1/012029`: "convex hull linearization … **with binary variables**". Downstream = hydrogen production only.
- Guan et al. (2026) `10.1109/tsg.2026.3668984`; Qi et al. (2026) `10.1016/j.epsr.2025.112653`; Li et al. (2022) `10.1109/icpet55165.2022.9918380` — all `[title-only]`, multi-stack/multi-unit scheduling, no ammonia downstream.
- Qiu et al. (2026), `10.3390/en19071712`: MILP with "**Independent control strategies … designed for each electrolyzer**". Downstream = hydrogen sales.

**Downstream ramp-limited continuous process — present as *concept*, absent as *constraint*:**
- Cheng & Ji (2026), `10.3390/en19122807` — the **only** paper that puts discrete electrolyser states and "flexible ammonia synthesis" in one MILP. But the abstract gives **no** ammonia-loop min load, ramp limit, or min-up/down constraint, and reports no cycling metric for the loop. So the integration may exist in the full text but **is not evidenced in this file**.
- Wang, Wang, Li & Zhao (2026), `10.1109/nesp70395.2026.11622181` — "**Maintenance-Aware Thermal-Ready Methanol Synthesis**" `[title-only]`. "Thermal-ready" strongly suggests keeping a synthesis unit within a thermal-operability window, i.e. exactly the ramp-limited-continuous-process concern — **but for methanol, and unverifiable here.**
- Mucci, Mitsos & Bongartz (2023), `10.1016/j.est.2023.108614` — "**Flexible operation or intermediate storage?**" `[title-only]`, methanol.

**Statement:** No evidence found in these files of a model that jointly (i) carries integer/binary electrolyser module-commitment variables and (ii) applies explicit min-load, ramp-rate, or minimum-up/down constraints to the **downstream ammonia synthesis loop**, with the coupling between them made explicit and the resulting switching behaviour reported. Cheng & Ji (2026) is the nearest miss; Travaglini et al. (2026) is the nearest upstream-only precedent; Wang et al. (2026, methanol) is the nearest downstream-only precedent.

### (e) The phrase "minimum load" or "turndown" applied to ammonia synthesis in an OPTIMISATION (not simulation) context?

**No evidence found in these files of the phrase "minimum load" applied to ammonia synthesis in any context.**

Verified precisely:
- **"minimum load" → zero matches** across all 15 files.
- **"turndown" / "turn-down" → exactly one match**, and it is the closest thing in the corpus:
  > "With the 2030 cost structure, battery storage offers better integration with wind systems and flexible operation, even at **low levels of turndown**."
  > — Pistolesi, Giaconia, Bassano & De Falco (2025), *Fuels*, `10.3390/fuels6020039`
- The same paper supplies the corpus's only **operationalised** minimum-load-like parameter:
  > "a **flexibility factor (ratio between the minimum operating capacity and the nominal capacity of the plant) of 20%** offers the most cost-effective solution, but production is scaled down to 64 tpd"
- **Is that an optimisation context?** It is an **LCOA sensitivity/design optimisation** — the objective is minimising production cost over "different combinations of process design choices and flexibility". It is **not** an hourly dispatch optimisation, has no unit-commitment or switching variables, and reports no cycling. So: the concept is present in a **techno-economic optimisation**, and **absent from any dispatch optimisation**.
- Other near-misses, none of which is a minimum load: Spatolisano & Kiss (2026) report a **separation performance** limit ("conventional condensation removes **less than 10% of NH₃ per pass**"), not a loop turndown limit. Pfromm & Aframehr (2022) fix a **production scale** ("1000 metric tons … per day"), not a minimum. Katjipaha et al. (2026) optimise **pressure** ("180–240 bar"), not load.

**Statement:** No evidence found in these files of "minimum load" applied to ammonia synthesis anywhere, and no evidence found of "turndown" applied to ammonia synthesis in an optimisation context except in Pistolesi et al. (2025), which is a **techno-economic (LCOA) optimisation**, not a dispatch optimisation.

### C2 summary table of empty cells

| Gap | Verdict |
|---|---|
| (a) Optimisation constraining ammonia-loop stability/cycling/switching | **No evidence found in these files.** Constraints of this type appear for electrolysers only; ammonia-loop dynamics papers are all `[title-only]`. |
| (b) Preregistered / protocol-locked selection of operational-stability indicators | **No evidence found in these files.** Zero occurrences of "preregist". Nearest analogues are in construction reporting (Delphi), traffic safety (ML feature selection), and environmental evidence synthesis (protocol sensitivity). |
| (c) Metric redundancy / robustness / incremental information | **No evidence found in these files** for redundancy and incremental information. Robustness-by-indicator-removal exists once (Du & Sun 2026), for risk indicators, in a non-operability context. |
| (d) Integer electrolyser module commitment coupled to a ramp-limited continuous downstream process | **No evidence found in these files** of the complete integration. Both halves exist separately; the nearest combined attempt (Cheng & Ji 2026) does not evidence the ammonia-side ramp constraints in its abstract. |
| (e) "Minimum load"/"turndown" for ammonia synthesis in an optimisation context | **No evidence found in these files** for "minimum load" (phrase absent entirely) or for "turndown" in a dispatch optimisation. One techno-economic-optimisation occurrence (Pistolesi et al. 2025, 20% flexibility factor; "low levels of turndown"). |

**Additional structural gap worth noting:** of all 274 entries, **none** reports a wind-PV-AEL-H₂-storage-Haber-Bosch **hourly dispatch** study for a specific Inner Mongolia site. The only China-related hits are title-only (`10.52202/081497-0108`, `10.1016/j.energy.2026.142307`) or concern Northwest China hydrogen-only systems (`10.3390/en19071712`, `10.3389/fenrg.2023.1305492`). The 42.23N 119.22E site does not appear.

---

# PART D — THREE CANDIDATE PAPER LINES

All three assume the same assets: a modular MILP dispatch model of a wind-PV-AEL-H₂-storage-Haber-Bosch plant (130 MW AEL, 100 kt/y NH₃, hourly, renewables.ninja 2022–2025 at 42.23N 119.22E), plus a preregistered 17-candidate operational-stability indicator framework with validity / redundancy / incremental-information / robustness gates.

**Ranking rationale (stated up front):** the corpus is >82% title-only, so the *strongest* defensible claims are those where (i) the gap is verifiable as empty from these files, and (ii) the result is a number a reader can argue with. Line 1 wins on both. Line 2 has the largest novelty but the weakest energy-systems result. Line 3 has the smallest novelty because Salmon & Bañares-Alcántara (2023) and Mucci et al. (2023) already occupy adjacent ground.

---

## Rank 1 — "The cost of keeping the ammonia loop stable": stability-constrained modular dispatch on 4 years of real Inner Mongolia data

**Central question.** In a 130 MW AEL / 100 kt-y NH₃ off-grid-or-weak-grid plant, what does it cost — in LCOA, NH₃ output, curtailment, and H₂ buffer cycling — to honour explicit operability constraints on the ammonia synthesis loop, and does coupling integer electrolyser module commitment to a ramp-limited HB loop change the optimal design compared with the continuous-relaxation models that dominate the literature?

**Novelty claim.** Per Part C(d) and C(e), **no evidence found in these files** of a model that carries integer electrolyser module-commitment variables *and* explicit min-load / ramp-rate / minimum-up-down constraints on the downstream ammonia loop, with the coupling explicit and switching behaviour reported. Cheng & Ji (2026) is the nearest miss (it does not evidence ammonia-side ramp constraints); Travaglini et al. (2026) is upstream-only; Wang et al. (2026, methanol) is `[title-only]`. The contribution is therefore (i) the coupled formulation and (ii) the *quantified* stability–economics trade-off at a real site over four real years — with the claim scoped as "first in this corpus", not "first in the world".

**Evidence needed.**
1. A MILP with binary module-commitment for the AEL fleet (start-up/shutdown, hot/cold, min continuous operating time, as precedented by `10.2139/ssrn.7197893`) **plus** HB-loop constraints (min stable load, ramp limit, min up/down) applied to the synthesis unit.
2. **Defensible provenance for the HB constraint parameters.** This is the make-or-break item. From this corpus the only anchor is Pistolesi et al. (2025) "flexibility factor … of **20%**" (`10.3390/fuels6020039`), plus the qualitative flexibility assumption of Wang et al. (2022/2023) and the process-agility enablers of Smith & Torrente-Murciano (2021) and Spatolisano & Kiss (2026). **A parameter sweep with the 20% case flagged as literature-anchored is the honest design** — do not assert a single min-load value as fact.
3. Four-year hourly dispatch under at least three regimes: (a) continuous relaxation of module commitment, (b) integer module commitment with a fixed-load HB loop, (c) integer module commitment with a ramp-limited HB loop. Report ΔLCOA, ΔNH₃, Δcurtailment, H₂-buffer throughput/cycling, stack start counts.
4. The 17-indicator framework applied to the (c) schedule, with the validity/redundancy/incremental-information/robustness gates reported — this is what converts "another MILP" into a measurement contribution.
5. Sensitivity to uncertainty: Salmon & Bañares-Alcántara (2023) frame the two hard problems as "Inability to predict the weather, and to rapidly adjust the operating rate of Haber–Bosch synthesis". At minimum, report dispatch under perfect vs. forecast-error-injected renewables.

**Main reviewer objection.** *"The HB operability parameters are not yours and not verifiable; without a plant you cannot know the true min load or ramp limit, so the headline cost-of-stability number is an artefact of assumed parameters."* — Mitigation: frame the deliverable as a **parametric cost-of-stability surface** rather than a point estimate, and show which indicators change *sign* or ranking across the parameter range (this is exactly the protocol-sensitivity logic of `10.2139/ssrn.6517459`, transposed).

**Why Rank 1.** It answers a question the corpus demonstrably does not answer, produces falsifiable numbers, and the indicator framework is load-bearing rather than decorative.

---

## Rank 2 — Preregistered selection and validation of operational-stability indicators for flexible power-to-ammonia

**Central question.** Of 17 candidate operational-stability indicators for a flexible wind-PV-AEL-H₂-HB plant, which survive formal validity, redundancy, incremental-information, and robustness gates — and does the surviving parsimonious subset change the ranking of candidate plant designs?

**Novelty claim.** Per Part C(b) and C(c): **no evidence found in these files** of a preregistered or protocol-locked selection of operational-stability indicators, and **no evidence found** of any redundancy or incremental-information analysis among candidate metrics in an energy-operations context. The corpus contains only distant analogues: Delphi-based theme selection for construction reporting (`10.3390/su17073014`), ML feature selection for driving risk (`10.3390/su18052423`), indicator-removal robustness for grid-service risk (`10.3390/su18021002`), and protocol-sensitivity with sign reversal in environmental evidence synthesis (`10.2139/ssrn.6517459`). The explicit move — **a preregistered, protocol-locked indicator-selection protocol with redundancy and incremental-information gates, applied to operability of a flexible industrial load** — is genuinely unclaimed here.

**Evidence needed.**
1. A **timestamped preregistration document** in a public registry or an OSF/Zenodo deposit, with the 17 candidates, the four gates, the pass/fail thresholds, and the decision rule fixed *before* seeing model output. Without a verifiable timestamp the novelty claim collapses to "we chose some indicators".
2. Full 17×17 association structure (rank correlation, clustering) as the **redundancy** gate; a conditional-contribution test (e.g. nested-model comparison or mutual information conditional on the retained set) as the **incremental-information** gate — note that **"mutual information" and "incremental information" have zero occurrences in this corpus**, so the formalism must be imported from outside it and cited there.
3. **Robustness** gate in the sense of `10.2139/ssrn.6517459`: perturb protocol choices (time resolution, scenario year, weather-year subset, curtailment accounting convention) and report whether each indicator's *sign* and *rank order* survive. Report the median swing in percentage points, as that paper does, so the result is comparable in form.
4. **A decision-relevance demonstration.** Compute the reduced indicator set for ≥3 candidate designs and show the ranking is either preserved (parsimony is safe) or changed (the full set was misleading). This is the paper's whole payoff.
5. Full transparency on the dispatch model that generates the indicator values, since the indicators are only as credible as the schedule.

**Main reviewer objection.** *"This is indicator engineering, not an energy-systems contribution; and the choice of 17 candidates is arbitrary."* — Mitigation: the decision-relevance demonstration in item 4 is non-negotiable, and the 17 candidates must be justified as the union of (i) metrics used in the corpus's dispatch literature (start counts, min continuous operating time, stable-operation share — cf. `10.3390/su18073423`, `10.2139/ssrn.7197893`, `10.2139/ssrn.7120226`) and (ii) the operability-as-transient-output-constraint framing (`10.1016/b978-0-323-85159-6.50059-2`).

**Why Rank 2.** Highest novelty, but its value depends entirely on the decision-relevance demonstration, and Q1 energy journals rarely reward a methods-only paper that leaves the energy result implicit. If the team writes only one paper, fold this in as Rank 1's measurement layer.

---

## Rank 3 — Forecast error, buffer sizing, and stability margin: how much H₂ storage substitutes for operability?

**Central question.** Over 2022–2025 Inner Mongolia weather, how much H₂ buffer capacity substitutes for ammonia-loop operability margin — i.e., what is the exchange rate between storage hours and permitted ramp/min-load flexibility — and how does imperfect forecasting shift that exchange rate?

**Novelty claim.** The flexibility-versus-storage trade is already claimed in this corpus for methanol (`10.1016/j.est.2023.108614`, "**Flexible operation or intermediate storage?**"), and imperfect forecasting for HB is already the stated subject of Salmon & Bañares-Alcántara (2023). The defensible residual novelty is narrow and specific: a **quantified substitution curve** between H₂ buffer capacity and ammonia-loop operability limits, on four years of real site data, with **formal H₂ buffer sizing criteria** anchored to Isella & Manca (2025) (`10.1016/j.ijhydene.2024.12.228`, "A **general criterion** for the design and operation of flexible hydrogen storage in Power-to-X processes") — a paper whose full text is unavailable here and would need retrieval to position against. Also note the corpus gives **no hydrogen storage duration in hours or days** for any ammonia plant (Part B6), so duration-based reporting is itself a small gap-filler.

**Evidence needed.**
1. Forecast-error model (day-ahead wind/PV error) calibrated to the site; imperfect-forecast dispatch vs perfect-foresight upper bound.
2. A 2-D sweep over (H₂ buffer capacity × HB min-load/ramp allowance) producing an iso-LCOA or iso-curtailment surface; identify the substitution frontier and where it saturates.
3. Report storage as **duration** (hours/days), explicitly filling the Part B6 gap, alongside kg.
4. Cross-check against Franco et al. (2025) (`10.3390/hydrogen6010007`) diminishing-returns finding on added storage ("added capacity offering minimal gains in hydrogen production and raising economic concerns") — a useful qualitative prior to test at ammonia scale.
5. The 17-indicator framework applied to show that the storage-optimal design is or is not also the stability-optimal design.

**Main reviewer objection.** *"This is a re-run: Salmon & Bañares-Alcántara already coupled imperfect forecasting to HB flexibility, and Mucci et al. already asked flexible-operation-versus-storage. Changing the molecule to ammonia and the location to Inner Mongolia is a case study, not a contribution."* — Mitigation: the substitution **exchange rate** (a quantitative frontier), not the existence of the trade-off, must be the claim; and the storage-duration reporting debt plus the stability-indicator overlay are the differentiators.

**Why Rank 3.** Lowest differentiation risk-adjusted return: two adjacent papers already occupy the conceptual space, and both are `[title-only]` here, meaning the team must retrieve them before it can even prove non-overlap.

---

## Cross-cutting recommendations for the team

1. **Retrieve full texts before committing to a line.** In priority order: (i) Pistolesi, Facchino, Bassano & Giaconia (2026), `10.1016/j.ijhydene.2026.155281` — closest to gaps (a)/(e); (ii) Rosbo et al. (2025/2026), `10.2139/ssrn.5379004` / `10.1016/j.compchemeng.2026.109614` — the most on-target A3 work; (iii) Isella & Manca (2025), `10.1016/j.ijhydene.2024.12.228` — the buffering criterion; (iv) Cheng & Ji (2026), `10.3390/en19122807` — open access, and the key near-miss for gap (d); (v) Fahr et al. (2025), `10.1016/j.ijhydene.2025.01.039`; (vi) Valizadeh & Hayati (2025), `10.1016/j.rineng.2025.106978` for the indicator-selection framing.
2. **Re-run the failed queries.** q09 (grid/curtailment/market) and q15 (operability constraints) produced essentially nothing on-topic, and q13 (Inner Mongolia/China) returned unrelated biology and medicine. Three of fifteen queries are effectively void, so the absence of evidence in A6 and the inner-Mongolia case-study space should be **re-tested with better query strings before being claimed as a literature gap**.
3. **Treat the 82.8% abstract gap as the dominant limitation of this review.** Every `[title-only]` judgement here is a judgement about a title. Where I wrote "no evidence found in these files", the correct reading is "no evidence in these 15 abstract sets" — not "no such paper exists".

---

## Provenance note

Every DOI, author-year, journal, verbatim fragment and number in this report was read directly from `project/lit/q01_pta_flexible.txt` … `q15_operability.txt` in this session. No web search was performed. Negative findings (a)–(e) and the absences listed in Part B were verified by full-corpus regex search in addition to reading: "preregist", "ramp"/"ramping", "minimum load", "redundan", "incremental information", "mutual information", "collinear", "minimum up"/"min up"/"minimum down"/"min down", "kWh/Nm³". Where the source abstract contained no number, no number was supplied.
