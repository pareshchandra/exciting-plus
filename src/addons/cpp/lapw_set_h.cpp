#include "lapw.h"

inline void L3_sum_gntyry(int lm1, int lm2, double *v, std::complex<double>& zsum)
{
    for (unsigned int k = 0; k < p.L3_gntyry(lm1, lm2).size(); k++)
    {
        int lm3 = p.L3_gntyry(lm1, lm2)[k];
        zsum += p.gntyry(lm3, lm1, lm2) * v[lm3];
    }
}

void lapw_set_h(int ngp,
                int ldh,
                tensor<int,1>& igpig,
                tensor<double,2>& vgpc,
                tensor<std::complex<double>,1>& veffig,
                tensor<std::complex<double>,2>& capwalm,
                tensor<double,5>& apwfr,
                tensor<double,3>& apwdfr,
                tensor<double,4>& hmltrad,
                tensor<std::complex<double>,2>& h)
{
    std::vector< std::complex<double> > zv(ngp);
    tensor<std::complex<double>,2> zm(ngp, p.wfmt_size_apw);

    for (unsigned int ias = 0; ias < geometry.atoms.size(); ias++)
    {
        Atom *atom = &geometry.atoms[ias];
        Species *species = atom->species;

        for (unsigned int j2 = 0; j2 < atom->ci_apw.size(); j2++)
        {
            int l2 = atom->ci_apw[j2].l;
            int io2 = atom->ci_apw[j2].order;
            int lm2 = atom->ci_apw[j2].lm;
            int idxrf2 = atom->ci_apw[j2].idxrf;

            memset(&zv[0], 0, ngp * sizeof(std::complex<double>));
            
            for (unsigned int j1 = 0; j1 < atom->ci_apw.size(); j1++)
            {
                int lm1 = atom->ci_apw[j1].lm;
                int idxrf1 = atom->ci_apw[j1].idxrf;
                
                std::complex<double> zsum(0, 0);
                L3_sum_gntyry(lm1, lm2, &hmltrad(0, idxrf1, idxrf2, ias), zsum);

                if (abs(zsum) > 1e-14) 
                    for (int ig = 0; ig < ngp; ig++) 
                        zv[ig] += zsum * capwalm(ig, atom->offset_apw + j1); 
            }
            
            for (unsigned int io1 = 0; io1 < species->apw_descriptors[l2].radial_solution_descriptors.size(); io1++)
            {
                double t1 = 0.5 * pow(species->rmt, 2) * apwfr(species->nrmt - 1, 0, io1, l2, ias) * apwdfr(io2, l2, ias); 
                for (int ig = 0; ig < ngp; ig++) 
                    zv[ig] += t1 * capwalm(ig, atom->offset_apw + atom->ci_apw_by_lmo(lm2, io1));
            }
            memcpy(&zm(0, atom->offset_apw + j2), &zv[0], ngp * sizeof(std::complex<double>));
        }
    }
    std::complex<double> zone(1, 0);
    std::complex<double> zzero(0, 0);
    zgemm<gemm_worker>(0, 2, ngp, ngp, p.wfmt_size_apw, zone, &zm(0, 0), ngp, &capwalm(0, 0), ngp, zzero, &h(0, 0), ldh);

    for (unsigned int ias = 0; ias < geometry.atoms.size(); ias++)
    {
        Atom *atom = &geometry.atoms[ias];
        Species *species = atom->species;

        for (unsigned int j2 = 0; j2 < atom->ci_lo.size(); j2++) // loop over columns (local-orbital block) 
        {
            int l2 = atom->ci_lo[j2].l;
            int lm2 = atom->ci_lo[j2].lm;
            int ilo2 = atom->ci_lo[j2].idxlo;
            int idxrf2 = atom->ci_lo[j2].idxrf;
            
            // apw-lo block of the Hamiltonian
            for (unsigned int j1 = 0; j1 < atom->ci_apw.size(); j1++) // loop over rows
            {
                int lm1 = atom->ci_apw[j1].lm;
                int idxrf1 = atom->ci_apw[j1].idxrf;
                
                std::complex<double> zsum(0, 0);
                L3_sum_gntyry(lm1, lm2, &hmltrad(0, idxrf1, idxrf2, ias), zsum);
                        
                if (abs(zsum) > 1e-14)
                    for (int ig = 0; ig < ngp; ig++)
                        h(ig, ngp + atom->offset_lo + j2) += zsum * capwalm(ig, atom->offset_apw + j1);
            }

            // lo-lo block of the Hamiltonian 
            for (unsigned int j1 = 0; j1 <= j2; j1++)
            {
                int lm1 = atom->ci_lo[j1].lm;
                int ilo1 = atom->ci_lo[j1].idxlo;
                int idxrf1 = atom->ci_lo[j1].idxrf;
                
                std::complex<double> zsum(0, 0);
                L3_sum_gntyry(lm1, lm2, &hmltrad(0, idxrf1, idxrf2, ias), zsum);
    
                h(ngp + atom->offset_lo + j1, ngp + atom->offset_lo + j2) += zsum;
            }
        }
    }
    
    int iv[3];
    for (int j2 = 0; j2 < ngp; j2++) // loop over columns
    {
        int ig2 = igpig(j2) - 1;
        double v2[3];
        for (int k = 0; k < 3; k++) v2[k] = vgpc(k, j2);
        for (int j1 = 0; j1 <= j2; j1++) // for each column loop over rows
        {
            for (int k = 0; k < 3; k++) iv[k] = p.ivg(k, igpig(j1) - 1) - p.ivg(k, ig2);
            int ig = p.ivgig(iv[0], iv[1], iv[2]);
            double t1 = 0.5 * (vgpc(0, j1) * v2[0] + vgpc(1, j1) * v2[1] + vgpc(2, j1) * v2[2]);
            h(j1, j2) += veffig(ig) + t1 * p.cfunig[ig];
        }
    }
}


