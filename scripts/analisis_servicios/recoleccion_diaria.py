# Recoleccion diaria con el mapa de turnos (dos panoramas). Correr desde la raiz de APP_nuevoinforme despues de propuesta_turnos_v2.py (genera gol.pkl y eq_all.pkl). Usa salidas/circuitos_con_turno.geojson.
import pandas as pd, numpy as np, json, math
UP=''
DOW=['Lun','Mar','Mie','Jue','Vie','Sab','Dom']
# capacity from planilla (last 3 months)
d=pd.read_csv(UP+'db/disponibilidad/disponibilidad_camiones.csv'); d.columns=[c.strip() for c in d.columns]
d['F']=pd.to_datetime(d.FECHA,dayfirst=True); d=d[(d.F>='2026-07-15')&(d.F<='2026-10-14')]
d['dow']=d.F.dt.dayofweek; d['crews']=d[['CHOF','AUX']].min(axis=1)
cap=d.groupby(['TURNO','dow'])[['CAM. INICIO','CAM. USADOS','CHOF','AUX','crews']].mean()
print(cap.round(1).unstack(0).to_string())
# fixed load C_110-116
x=pd.read_pickle('eq_all.pkl').rename(columns={'eq':'q'}); x['dow']=x.Fecha.dt.dayofweek
dates=pd.date_range('2025-10-15','2026-10-14'); ndow=pd.Series(dates.dayofweek).value_counts().sort_index().values
TT={'Matutino':'M','Vespertino':'V','Nocturno':'N'}; x['t']=x.Turno_levantado.astype(str).map(TT)
fix=x[x.bloque=='C110_116'].groupby(['t','dow']).q.sum().unstack(fill_value=0).reindex(columns=range(7),fill_value=0)/ndow
print('C110 fixed',fix.round(1))
# sizes
A=pd.read_excel(UP+'salidas/analisis_servicios_viajes_2025-10-15_2026-10-14.xlsx',sheet_name='Circuito_dia_turno'); A['Fecha']=pd.to_datetime(A.Fecha)
pos=A[A.Fecha>='2026-07-15'].groupby('Circuito_corto').contenedores_segun_posiciones.median()
g=pd.read_pickle('gol.pkl'); g=g[(g.contenedor_activo=='S')&(g.Fecha>='2026-07-15')]
szg=g.groupby(['Circuito_corto','Fecha']).gid.nunique().groupby('Circuito_corto').median()
geo=json.load(open('salidas/circuitos_con_turno.geojson'))
circ=[(f['properties']['NOMENCLATURA_ABREVIADA'],f['properties']['turno']) for f in geo['features']]
PROD={'N':95,'M':60,'V':53}; RIT={'N':23.1,'M':18.0,'V':14.4}
rows=[]
for c,t in circ:
    if c.startswith('B_0'): continue
    s=pos.get(c, np.nan); s=szg.get(c) if pd.isna(s) else s
    rows.append(dict(circuito=c,turno=t,contenedores=s))
C=pd.DataFrame(rows); print(C.groupby('turno').contenedores.agg(['count','sum']))
C.to_pickle('circ.pkl'); cap.to_pickle('cap.pkl'); fix.to_pickle('fix.pkl')
bsz={c:szg.get(c) for c,t in circ if c.startswith('B_0')}; print('B0x',bsz,sum(bsz.values()))
import pandas as pd, numpy as np, math
DOW=['Lun','Mar','Mie','Jue','Vie','Sab','Dom']
cap=pd.read_pickle('cap.pkl'); fix=pd.read_pickle('fix.pkl'); C=pd.read_pickle('circ.pkl')
PROD={'N':95,'M':60,'V':53}; RIT={'N':23.1,'M':18.0,'V':14.4}
def g(col,t,dd): 
    try: return cap.loc[(t,dd),col]
    except KeyError: return 0.0
noc=C[C.turno=='nocturno']; diu=C[C.turno=='diurno'].sort_values('contenedores',ascending=False)
res={}
for pan in (1,2):
    rows=[]; plan=[]
    for dd in range(7):
        trucks={t:g('CAM. INICIO',t,dd) for t in 'MVN'}
        crews={t:g('crews',t,dd) for t in 'MVN'}
        chof={t:g('CHOF',t,dd) for t in 'MVN'}; aux={t:g('AUX',t,dd) for t in 'MVN'}
        need={t:fix.loc[t,dd] for t in 'MVN'}
        if dd!=5: need['N']+=noc.contenedores.sum()/PROD['N']
        if pan==1: avail={t:min(trucks[t],crews[t]) for t in 'MVN'}
        else:
            pool=sum(crews.values())
            avail={t:trucks[t] for t in 'MVN'}  # trucks per turno; people checked as pool
        # assign diurno circuits: mañana first, then tarde (not Sunday)
        for _,r in diu.iterrows():
            nM=r.contenedores/PROD['M']; nV=r.contenedores/PROD['V']
            def ok(t,n):
                if need[t]+n>avail[t]+1e-9: return False
                if pan==2 and sum(need.values())+n>pool+1e-9: return False
                return True
            if ok('M',nM): need['M']+=nM; plan.append((r.circuito,DOW[dd],'M',nM))
            elif dd!=6 and ok('V',nV): need['V']+=nV; plan.append((r.circuito,DOW[dd],'V',nV))
            else: plan.append((r.circuito,DOW[dd],'falta',nM))
        falta=sum(p[3] for p in plan if p[1]==DOW[dd] and p[2]=='falta')
        rows.append(dict(dia=DOW[dd],**{f'cam_{t}':trucks[t] for t in 'MVN'},**{f'cuad_{t}':crews[t] for t in 'MVN'},
                         **{f'usa_{t}':need[t] for t in 'MVN'},falta_M=falta,
                         pool=sum(crews.values()),usa_total=sum(need.values())+falta))
    res[pan]=(pd.DataFrame(rows),pd.DataFrame(plan,columns=['circuito','dia','turno','camiones']))
for pan,(r,p) in res.items():
    print('PANORAMA',pan); print(r.round(1).to_string()); print(p.turno.value_counts()); print(p[p.turno!='M'].groupby(['dia','turno']).circuito.apply(list))
import pickle; pickle.dump(res,open('diaria_res.pkl','wb'))
# per circuit table
C['serv_sem']=np.where(C.turno=='nocturno',6,7)
C['cam_serv']=np.where(C.turno=='nocturno',C.contenedores/95,C.contenedores/60)
C['horas_serv']=np.where(C.turno=='nocturno',C.contenedores/23.1,C.contenedores/18.0)
C['cam_sem']=C.cam_serv*C.serv_sem
print(C.round(2).sort_values(['turno','circuito']).to_string()); print(C.groupby('turno')[['cam_sem']].sum())
C.to_pickle('circ2.pkl')
