# Literature search running notes (agent-reach unavailable; web_search only)

## CRITICAL METHOD LIMITATION (must be reported)
- `web_search` in this session returns ONLY title+URL lists (no abstracts, no snippets, no answer summaries).
- Direct HTTP from pwsh is BLOCKED: curl to api.crossref.org / api.openalex.org / r.jina.ai / baidu all return HTTP code 000.
- `mcporter` has only `node_repl` configured and fails with `spawn EPERM` (documented sandbox boundary for piped stdio).
- => Metadata (title/journal/URL) is VERIFIED. Numeric values require source verification and are flagged.

---

## THEME 1.1 — Modularity / integer module commitment

| # | Source (verified title + URL) | Notes |
|---|---|---|
| T1-01 | "Model predictive supervisory control for multi-stack electrolyzers using multilinear modeling" — IJHE — https://www.sciencedirect.com/science/article/pii/S0360319925048505 | multi-stack supervisory MPC; multilinear model (=> MINLP-ish) |
| T1-02 | "Robust dispatch of multi-electrolyzer systems for renewable energy hydrogen production under wind forecast uncertainty" — Applied Energy (S0306261926001352) — https://www.sciencedirect.com/science/article/abs/pii/S0306261926001352 | multi-electrolyzer robust dispatch |
| T1-03 | "Multi-objective optimal modular design of PEM electrolyzers for efficient and scalable green hydrogen production plants" — J. Power Sources (S0378775325003465) — https://www.sciencedirect.com/science/article/abs/pii/S0378775325003465 | modular DESIGN (capacity per module), multi-objective |
| T1-04 | "Reconfiguring flexibility in renewable power-to-ammonia systems using molten-salt thermal energy storage in the ammonia synthesis loop: A coordinated electro-hydrogen-thermal scheduling approach" — Applied Energy (S0306261926012651) — https://www.sciencedirect.com/science/article/abs/pii/S0306261926012651 | P2A + TES in NH3 loop; coordinated scheduling |
| T1-05 | "Dynamic Operation and Control of a Multi-Stack Alkaline Water Electrolysis System with Shared Gas Separators and Lye Circulation: A Model-Based Study" — arXiv 2501.14576 — https://arxiv.org/abs/2501.14576 | multi-stack AEL, shared BoP, physics-based |
| T1-06 | "A Guided Safe Reinforcement Learning Framework for Adaptive Energy Management in Green Hydrogen Production Systems" — IEEE — https://ieeexplore.ieee.org/document/11517391 | "Multi-Unit PEM Electrolyzer Array Model" section; RL alternative to MILP |
| T1-07 | "Optimal capacity and multi-stable flexible operation strategy of green ammonia systems: Adapting to fluctuations in renewable energy" — Energy Conversion and Management — https://www.x-mol.com/paper/1807150423117197312 | "multi-stable" operation → discrete operating points |
| T1-08 | "Degradation-Aware Stochastic Scheduling of Multi-Stack Power-to-X Plants Under Joint Renewable and Electricity Price Uncertainty" — Energies 19(10):2482 — DOI 10.3390/en19102482 — https://www.mdpi.com/1996-1073/19/10/2482 | stochastic, degradation-aware, multi-stack; pmin<=p<=pmax with binary u_it |
| T1-09 | "Extended Load Flexibility of Industrial P2H Plants: A Process Constraint-Aware Scheduling Approach" — IEEE — https://ieeexplore.ieee.org/abstract/document/9846329 | process-constraint-aware P2H scheduling |
| T1-10 | "Lexicographic Power-Command Shaping for Homogeneous Electrolyzer Arrays in an Off-Grid Wind-to-Hydrogen System" — IEEE — https://ieeexplore.ieee.org/document/11662542 | LEXICOGRAPHIC command shaping of homogeneous array → directly relevant to module-commitment heuristics |
| T1-11 | Energy & Buildings?? — "Equations (23)-(26) formulate the unit-commitment logic of the electrolyzer array" — Electronics (MDPI) 15(8):1697 — https://www.mdpi.com/2079-9292/15/8/1697 | explicit unit-commitment logic for electrolyzer array |
| T1-12 | "Impact of power supply fluctuation and part load operation on the efficiency of alkaline water electrolysis" — IJHE (S0378775323000046) — https://www.sciencedirect.com/science/article/pii/S0378775323000046 | AEL part-load efficiency; experimental |

## THEME 1.3 — discrete-continuous, decomposition
- "Optimal design of energy storage-supply systems using a multi-objective evolutionary algorithm and mixed-integer linear programming with a two-stage rolling horizon method" — Energy (S0360544225036126) — https://www.sciencedirect.com/science/article/pii/S0360544225036126
- "Integrated Spatial and Multiperiod Optimization of Morocco's Green Hydrogen Supply Chain Using MILP and a FlexSim/FloWorks Based Digital Twin Simulation" — MDPI (2673-4141/7/3/130) — https://www.mdpi.com/2673-4141/7/3/130
- "Polynomial Time Algorithms and Extended Formulations for Unit Commitment Problems" — arXiv 1608.00042 — https://ar5iv.labs.arxiv.org/html/1608.00042  [tractability of integer commitment]

## THEME 1.4 — storage inventory / min pressure heel
- **HARD NUMBER FOUND**: "A minimum inventory level inside each tank should be maintained so that the tank pressure does not fall below 70 bar" — "A Stochastic Programming Approach for the Planning and Operation of a Power to Gas Energy Hub with Multiple Energy Recovery Pathways" — Energies 10(7):868 — https://www.mdpi.com/1996-1073/10/7/868  [min pressure heel = 70 bar]
- "Integrated Design and Scheduling of Hydrogen Processes under Uncertainty: A Quantile Neural Network Approach" — Ind. Eng. Chem. Res. (10.1021/acs.iecr.5c03288) — https://pubs.acs.org/doi/full/10.1021/acs.iecr.5c03288

## THEME 2 — metrics
- "A review of power system planning and operational models for flexibility assessment in high solar energy penetration scenarios" — Solar Energy (S0038092X20307489) — https://www.sciencedirect.com/science/article/abs/pii/S0038092X20307489
- "Enhancing Electric Grid Flexibility for the Integration of Variable Renewable Energy: Challenges, Innovations, and Future Directions" — IEEE — https://ieeexplore.ieee.org/abstract/document/11370851
- "A framework to identify and prioritise the key sustainability indicators: Assessment of heating systems in the built environment" — Sustainable Cities and Society (S2210670723002408) — https://www.sciencedirect.com/science/article/pii/S2210670723002408 — [indicator PRIORITISATION; notes "abundance of SIs is problematic"]
- "Indicators for the optimization of sustainable urban energy systems based on energy system modeling" — http://oa.las.ac.cn/oainone/service/browseall/read1?ptype=JA&workid=JA202203111759338ZK
- "A review of electrolyzer-based systems providing grid ancillary services: current status, market, challenges and future directions" — Frontiers in Energy Research 12:1358333 — https://www.frontiersin.org/journals/energy-research/articles/10.3389/fenrg.2024.1358333/full
- "The discrete on/off operational abstraction adopted in this study is grounded in both physical characteristics of hydrogen-based..." — Sustainability (MDPI) 18(11):5443 — https://www.mdpi.com/2071-1050/18/11/5443
