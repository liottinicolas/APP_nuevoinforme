"""Propuesta de turnos por circuito: costo en camiones-turno (dia por dia).
Lee las salidas del analisis de servicios y flota y el geojson de la propuesta."""
import pandas as pd, numpy as np, json
# Correr desde la raiz de APP_nuevoinforme: python scripts/analisis_servicios/propuesta_turnos.py
import sys
S='salidas/'
GEO=sys.argv[1] if len(sys.argv)>1 else 'salidas/circuitos_con_turno.geojson'
A=S+'analisis_servicios_viajes_2025-10-15_2026-10-14.xlsx'; F=S+'flota_frecuencia_2025-10-15_2026-10-14.xlsx'
cdt=pd.read_excel(A,sheet_name='Circuito_dia_turno'); cdt['Fecha']=pd.to_datetime(cdt.Fecha)
vj=pd.read_excel(A,sheet_name='Viajes').set_index('Id_viaje_GOL')
e=cdt.assign(ids=cdt.viajes.astype(str).str.split(',')).explode('ids'); e['ids']=e.ids.str.strip().astype(float)
e['n']=e.groupby(['Fecha','Turno','Circuito_corto']).ids.transform('count')
e['cont']=e.total_contenedores/e.n
e['sh']=e.cont/e.groupby('ids').cont.transform('sum')   # each trip sums to 1
W=52+1/7; SCALE=93.72/(len(vj)/W)
e['eq']=e.sh*SCALE
DOW=['Lun','Mar','Mie','Jue','Vie','Sab','Dom']
dates=pd.date_range('2025-10-15','2026-10-14'); ndow=pd.Series(dates.dayofweek).value_counts().sort_index()
e['dow']=e.Fecha.dt.dayofweek
# per circuit x dow x turno weekly trucks
g=e.groupby(['Circuito_corto','Turno','dow']).eq.sum().unstack(fill_value=0)
g=g.div(ndow,axis=1)
print('check total weekly',g.values.sum())
# unvisited per circuit (night) -> weekly containers
cdt['nov']=cdt.total_contenedores-cdt.visitados
nov=cdt[cdt.Turno=='Nocturno'].groupby(['Circuito_corto',cdt.Fecha.dt.dayofweek]).nov.sum().unstack(fill_value=0).div(ndow,axis=1)
geo=json.load(open(GEO))
prop={f['properties']['NOMENCLATURA_ABREVIADA']:f['properties']['turno'] for f in geo['features']}
circ=sorted(set(cdt.Circuito_corto))
M=[c for c in circ if prop.get(c)=='diurno']; N=[c for c in circ if c not in M]
print(len(M),M); print(len(N))
LL=pd.read_excel(F,sheet_name='Lugar_libre')
cs=pd.read_excel(F,sheet_name='Circuitos_a_subir').set_index('Circuito_corto')
FM,FV=0.70,0.62; PRODN=84.77
def lib(sit,t):
    x=LL[(LL.situacion.str.startswith(sit))&(LL.Turno==t)].set_index('dia_semana').libre
    return np.array([x.get(d,0.0) for d in DOW])
def night(cs_): 
    sub=g.loc[(cs_, 'Nocturno'),:] if False else None
def nt(cl,t='Nocturno'):
    idx=[(c,t) for c in cl if (c,t) in g.index]; return g.loc[idx].sum().reindex(range(7),fill_value=0).values
res={}
for sit,key in [('Actual','hoy'),('A/D','sinAG')]:
    lm,lv,ln=lib(sit,'Matutino'),lib(sit,'Vespertino'),lib(sit,'Nocturno')
    need=nt(M)  # noct-eq trucks per dow moving to day
    mm=np.minimum(lm,need/FM); r=need-mm*FM
    vv=np.minimum(lv,r/FV); un=r-vv*FV
    freed=need
    ln2=ln+freed
    out=dict(need_eq=need.round(2).tolist(),mat=mm.round(2).tolist(),vesp=vv.round(2).tolist(),uncov_eq=un.round(2).tolist(),
             night_free_before=ln.round(1).tolist(),night_free_after=ln2.round(1).tolist(),
             tot_need=need.sum(),tot_mat=mm.sum(),tot_vesp=vv.sum(),tot_unc=un.sum(),pct=1-un.sum()/need.sum(),
             night_free_week_before=ln.sum(),night_free_week_after=ln2.sum())
    # weekly-sum method (doc's)
    Lm,Lv=lm.sum(),lv.sum(); T=need.sum(); m=min(Lm,T/FM); rr=T-m*FM; v=min(Lv,rr/FV); out['weekly_method']=dict(mat=m,vesp=v,unc=rr-v*FV)
    # remaining-night options with freed + free night (per dow)
    comp=nov.reindex(N).fillna(0).sum().reindex(range(7),fill_value=0).values/PRODN
    f5=cs.reindex(N).camiones_extra_semana_f5.sum(); f6=cs.reindex(N).camiones_extra_semana_f6.sum()
    out.update(rem_completar=comp.sum(), rem_f5=f5, rem_f6=f6, comp_dow=comp.round(2).tolist())
    # day leftover after move
    out['mat_left']=(lm-mm).sum(); out['vesp_left']=(lv-vv).sum()
    res[key]=out
res['M']=M; res['N']=N
res['moved_detail']={c:dict(night=float(nt([c]).sum()), day_now=float(nt([c],'Matutino').sum()+nt([c],'Vespertino').sum()),
     freq=float(cs.loc[c,'frecuencia_actual_semanal']), cps=float(cs.loc[c,'camiones_por_servicio']),
     dias=[DOW[i] for i in range(7) if nt([c])[i]>0.15]) for c in M}
res['night_total_N']=float(sum(nt(N))); res['night_total_M']=float(sum(nt(M)))

for k in ['hoy','sinAG']:
    o=res[k]; print(k,{x:(round(o[x],2) if not isinstance(o[x],(list,dict)) else o[x]) for x in o})
print(res['night_total_M'],res['night_total_N'])
for c,d in res['moved_detail'].items(): print(c,d)

# ---- export
D=DOW
rows=[]
for k,lab in [('hoy','Hoy (todos los municipios)'),('sinAG','A/D/E/F/G dejan el sistema')]:
    o=res[k]
    for i,d in enumerate(D):
        rows.append(dict(situacion=lab,dia=d,noche_que_pasa_eq=o['need_eq'][i],matutino_usado=o['mat'][i],vespertino_usado=o['vesp'][i],
                         vespertino_faltante=o['uncov_eq'][i]/FV,noche_libre_antes=o['night_free_before'][i],noche_libre_despues=o['night_free_after'][i]))
pordia=pd.DataFrame(rows)
res_sem=pordia.groupby('situacion',sort=False).sum(numeric_only=True).reset_index()
res_sem['pct_cubierto']=[res['hoy']['pct'],res['sinAG']['pct']]
circ_t=pd.DataFrame([dict(Circuito=c,turno_propuesto='diurno' if c in M else 'nocturno',
        nocturnos_semana=float(nt([c]).sum()),frecuencia_actual=float(cs.loc[c,'frecuencia_actual_semanal'])) for c in circ])
with pd.ExcelWriter(S+'propuesta_turnos_2025-10-15_2026-10-14.xlsx') as w:
    res_sem.round(2).to_excel(w,'Resumen',index=False); pordia.round(2).to_excel(w,'Por_dia',index=False); circ_t.round(2).to_excel(w,'Circuitos',index=False)
    pd.DataFrame({'Concepto':['Camion-turno equivalente','Lugar libre','Factor diurno','Asignacion'],
      'Definicion':['Cada viaje GOL se reparte entre sus circuitos segun contenedores; se escala a 93,7 camiones-turno/semana del doc de servicios',
       'Lugar_libre de flota_frecuencia (planilla menos uso p90), por dia de semana',
       'Matutino 0,70 y Vespertino 0,62 de los visitados nocturnos (hoja Productividad)',
       'Cada dia: primero manana libre, despues tarde; lo que no entra queda sin cubrir. Mismos dias de servicio que hoy']}).to_excel(w,'Definiciones',index=False)
