# Propuesta de turnos v2 (dos panoramas). Requiere pyreadr/pandas/scipy. Paso 1 genera eq_all.pkl desde historico_llenadoGol.rds filtrado (gol.pkl); paso 2 resuelve el MILP con run(situacion, panorama, F6).
import pandas as pd, numpy as np
df=pd.read_pickle('gol.pkl')
df=df[(df.Oficina=='IM')&(df.contenedor_activo=='S')]
df=df[~((df.Fecha.dt.dayofweek==5)&(df.Turno_levantado=='Nocturno'))].copy()
# grua rule
pc=df.groupby(['Id_viaje_GOL','Circuito_corto']).agg(k=('gid','size'),pmin=('Posicion','min'),pmax=('Posicion','max')).reset_index()
pc['dens']=pc.k/(pc.pmax-pc.pmin+1)
tr=pc.groupby('Id_viaje_GOL').agg(n=('k','sum'),nsmall=('k',lambda s:(s<=2).sum()),dmax=('dens','max'))
tr['grua']=(tr.n<=40)&((tr.nsmall>=3)|(tr.dmax<=0.5))
print('grua',tr.grua.sum())
df=df[~df.Id_viaje_GOL.isin(tr.index[tr.grua])]
x=df.groupby(['Id_viaje_GOL','Fecha','Turno_levantado','Circuito_corto'],observed=True).agg(k=('gid','size'),
   vis=('Levantado',lambda s: s.isin(['S','N']).sum())).reset_index()
x['eq']=x.k/x.groupby('Id_viaje_GOL').k.transform('sum')
x['mun']=x.Circuito_corto.str.split('_').str[0]
W=52+1/7
x['bloque']=np.where(x.mun.isin(list('ADEFG')),'AG',np.where(x.Circuito_corto.str.match(r'^C_11[0-6]$'),'C110_116',np.where(x.Circuito_corto.isin(['C_104','C_105']),'C104_105','analizados')))
print(x.groupby(['bloque','Turno_levantado'],observed=True).eq.sum().unstack()/W)
x.to_pickle('eq_all.pkl')
import pandas as pd, numpy as np, json, sys
from scipy.optimize import milp, LinearConstraint, Bounds
from scipy.sparse import lil_matrix
S='/mnt/user-data/uploads/APP_nuevoinforme/salidas/'
F='flota_frecuencia_2025-10-15_2026-10-14.xlsx'
x=pd.read_pickle('eq_all.pkl').rename(columns={'eq':'q'}); x['dow']=x.Fecha.dt.dayofweek
DOW=['Lun','Mar','Mie','Jue','Vie','Sab','Dom']
dates=pd.date_range('2025-10-15','2026-10-14'); ndow=pd.Series(dates.dayofweek).value_counts().sort_index().values
W=len(dates)/7
TT={'Matutino':'M','Vespertino':'V','Nocturno':'N'}
x['t']=x.Turno_levantado.astype(str).map(TT)
def prof(circs,t):  # trucks per dow (avg)
    s=x[x.Circuito_corto.isin(circs)&(x.t==t)].groupby('dow').q.sum().reindex(range(7),fill_value=0).values
    return s/ndow
FAC={'M':0.70,'V':0.62,'N':1.0}
M=['CH_110','CH_111','CH_112','CH_113','CH_114','CH_115','CH_116','CH_117','CH_118','C_101','C_102','C_103','C_106','C_107','C_108','C_109']
GONE=['C_104','C_105']
an=x[x.bloque=='analizados'].Circuito_corto.unique().tolist()
N=[c for c in an if c not in M]
LL=pd.read_excel(S+F,sheet_name='Lugar_libre')
def lib(sit,t):
    s=LL[LL.situacion.str.startswith(sit)&(LL.Turno==t)].set_index('dia_semana').libre
    return np.array([s.get(d,0.0) for d in DOW])
# circuit params
info={}
for c in M:
    n=x[(x.Circuito_corto==c)&(x.t=='N')]
    wk=n.q.sum()/W; serv=n.Fecha.nunique()/W
    Fc=max(3,int(round(serv)))
    info[c]=dict(night_wk=wk,serv=serv,F=Fc,e=wk/Fc, day_wk=x[(x.Circuito_corto==c)&(x.t!='N')].q.sum()/W)
# AG candidates (whole circuit, one shift)
ag=x[x.bloque=='AG']
cand=[]
for (c,t),g in ag[ag.t.isin(['M','V'])].groupby(['Circuito_corto','t']):
    wk=g.q.sum()/W; serv=g.Fecha.nunique()/W
    if serv<1.5: continue
    S_=int(round(serv)); 
    if S_>6: S_=6
    cand.append(dict(c=c,t=t,wk=wk,S=S_,e=wk/S_,free=prof([c],t)))
def run(sit,pan,F6=False,allow_swap=True):
    lm,lv,ln=lib(sit,'Matutino'),lib(sit,'Vespertino'),lib(sit,'Nocturno')
    # gone circuits free their capacity
    ln=ln+prof(GONE,'N'); lm=lm+prof(GONE,'M'); lv=lv+prof(GONE,'V')
    # moved circuits free night; their current small day services are part of the new day plan -> free them
    freedM=prof(M,'N'); ln=ln+freedM; lm=lm+prof(M,'M'); lv=lv+prof(M,'V')
    # remaining analyzed circuits: day services -> night (same dow; Sat stays day)
    dm,dv=prof(N,'M'),prof(N,'V')
    mv=np.array([d!=5 for d in range(7)],float)
    lm=lm+dm*mv; lv=lv+dv*mv; ln=ln-(dm*FAC['M']+dv*FAC['V'])*mv
    cands=cand if (pan==1 and allow_swap and sit=='Actual') else []
    # variables
    idx={}; k=0
    for c in M:
        for d in range(7):
            for t in 'MV': idx[('y',c,d,t)]=k; k+=1
    for c in M:
        for t in 'MV': idx[('h',c,t)]=k; k+=1
    for i,a in enumerate(cands):
        idx[('z',i)]=k; k+=1
        for d in range(7):
            if d!=5: idx[('w',i,d)]=k; k+=1
    for d in range(7):
        for t in 'MV':
            idx[('u',d,t)]=k; k+=1
            if pan==2: idx[('s',d,t)]=k; k+=1
    for d in range(7):
        if d!=5: idx[('un',d)]=k; k+=1
    nv=k; cost=np.zeros(nv); lb=np.zeros(nv); ub=np.ones(nv); integ=np.zeros(nv)
    rows=[]; lo=[]; hi=[]
    def add(coefs,l,h): rows.append(coefs); lo.append(l); hi.append(h)
    for c in M:
        Fc=6 if F6 else info[c]['F']; e=info[c]['e']
        add({idx[('y',c,d,t)]:1 for d in range(7) for t in 'MV'},Fc,Fc)
        for d in range(7):
            add({idx[('y',c,d,t)]:1 for t in 'MV'},0,1)
            if Fc<=3: add({idx[('y',c,dd%7,t)]:1 for dd in (d,d+1) for t in 'MV'},0,1)
            elif Fc<=4: add({idx[('y',c,dd%7,t)]:1 for dd in (d,d+1,d+2) for t in 'MV'},0,2)
        for d in range(7):
            for t in 'MV': cost[idx[('y',c,d,t)]]=e/FAC[t]; integ[idx[('y',c,d,t)]]=1
        add({idx[('h',c,'M')]:1,idx[('h',c,'V')]:1},1,1)
        for t in 'MV':
            integ[idx[('h',c,t)]]=1
            for d in range(7): add({idx[('y',c,d,t)]:1,idx[('h',c,t)]:-1},-1,0)
    for i,a in enumerate(cands):
        zi=idx[('z',i)]; integ[zi]=1; cost[zi]=0.5
        add({**{idx[('w',i,d)]:1 for d in range(7) if d!=5}, zi:-a['S']},0,0)
        for d in range(7):
            if d!=5:
                wi=idx[('w',i,d)]; integ[wi]=1
                add({wi:1,zi:-1},-1,0)
    for d in range(7):
        for t in 'MV':
            ui=idx[('u',d,t)]; ub[ui]=np.inf; cost[ui]=1000
            base=lm[d] if t=='M' else lv[d]
            co={idx[('y',c,d,t)]:info[c]['e']/FAC[t] for c in M}; co[ui]=-1
            for i,a in enumerate(cands):
                if a['t']==t: co[idx[('z',i)]]=-a['free'][d]
            if pan==2:
                si=idx[('s',d,t)]; ub[si]=8; cost[si]=0.5; co[si]=-1
            add(co,-np.inf,base)
        if pan==2: add({idx[('s',d,'M')]:1,idx[('s',d,'V')]:1},0,10)
    # night capacity per day: ln - shifted(s on that day, Sat shift drawn from Fri? -> spread) - swaps
    if pan==2:
        # weekly pool of shifted crews limited by weekly night free
        add({idx[('s',d,t)]:1 for d in range(7) for t in 'MV'},0,max(0,ln.sum()))
    for d in range(7):
        if d==5: continue
        co={}
        for i,a in enumerate(cands): co[idx[('w',i,d)]]=a['e']*FAC[a['t']]
        un=idx[('un',d)]; ub[un]=np.inf; cost[un]=1000; co[un]=-1
        add(co,-np.inf,max(ln[d],0))
    A=lil_matrix((len(rows),nv))
    for r,co in enumerate(rows):
        for j,v in co.items(): A[r,j]=v
    res=milp(cost,constraints=LinearConstraint(A.tocsr(),lo,hi),integrality=integ,bounds=Bounds(lb,ub),options={'time_limit':120})
    X=res.x
    plan=[]
    for c in M:
        for d in range(7):
            for t in 'MV':
                if X[idx[('y',c,d,t)]]>0.5: plan.append(dict(circuito=c,dia=DOW[d],turno={'M':'Matutino','V':'Vespertino'}[t],camiones=info[c]['e']/FAC[t]))
    plan=pd.DataFrame(plan)
    swaps=[dict(circuito=a['c'],turno_actual={'M':'Matutino','V':'Vespertino'}[a['t']],servicios_sem=a['S'],camiones_dia_sem=a['wk'],camiones_noche_sem=a['wk']*FAC[a['t']],
                noches=[DOW[d] for d in range(7) if d!=5 and X[idx[('w',i,d)]]>0.5]) for i,a in enumerate(cands) if X[idx[('z',i)]]>0.5]
    u={(DOW[d],t):X[idx[('u',d,t)]] for d in range(7) for t in 'MV'}
    s={(DOW[d],t):X[idx[('s',d,t)]] for d in range(7) for t in 'MV'} if pan==2 else {}
    ssum=sum(s.values()) if s else 0
    night_used_swaps=np.array([sum(a['e']*FAC[a['t']]*(X[idx[('w',i,d)]]>0.5) for i,a in enumerate(cands)) if d!=5 else 0 for d in range(7)])
    night_left=np.clip(ln-night_used_swaps,0,None); night_left_wk=night_left.sum()-ssum
    return dict(status=res.status,msg=res.message,plan=plan,swaps=swaps,u=u,s=s,ssum=ssum,
                lm=lm,lv=lv,ln=ln,night_left=night_left,night_left_wk=night_left_wk,
                day_M=plan[plan.turno=='Matutino'].camiones.sum() if len(plan) else 0,
                day_V=plan[plan.turno=='Vespertino'].camiones.sum() if len(plan) else 0,
                unc=sum(u.values()))
# improvements for remaining night circuits
cs=pd.read_excel(S+F,sheet_name='Circuitos_a_subir').set_index('Circuito_corto')
A_=pd.read_excel(S+'analisis_servicios_viajes_2025-10-15_2026-10-14.xlsx',sheet_name='Circuito_dia_turno')
A_['nov']=A_.total_contenedores-A_.visitados
comp=A_[(A_.Turno=='Nocturno')&A_.Circuito_corto.isin(N)].nov.sum()/W/84.77
imp=dict(completar=comp,f5=cs.reindex(N).camiones_extra_semana_f5.sum(),f6=cs.reindex(N).camiones_extra_semana_f6.sum(),
         day_to_night=sum((prof(N,'M')*0.7+prof(N,'V')*0.62)*np.array([d!=5 for d in range(7)])))
