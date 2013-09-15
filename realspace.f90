PROGRAM Real_Space_Solid

  use global_variables
  use parameters_module
  use omp_variables

  use esm_rgrid_module
  use esm_rshell_module
  use esm_cylindrical_test
  use ps_local_rs_module
  use esm_genpot_module
  use kinetic_esm_module

  use func2gp_module

  use rgrid_mol_module
  use ps_local_mol_module
  use eion_mol_module
  use ps_pcc_mol_module
  use ps_initrho_mol_module
  use ps_nloc2_mol_module
  use bc_mol_module
  use kinetic_mol_module
#ifndef _DRSDFT_
  use band_module
#endif

  use ps_gth_module

  use bcast_module

  implicit none

  real(8) :: ct0,ct1,et0,et1
  integer :: i,n,k,s,iter,m,ierr,i1,i2,i3
  real(8),allocatable :: esp0(:,:,:),force(:,:),forcet(:,:),vtmp(:)
  logical :: flag_conv=.false.
  logical :: flag_exit=.false.
  logical :: flag_end =.false.
  logical :: flag_scf =.false.

! --- start MPI ---

  call start_mpi_parallel

! --- global time counter start ---

  call global_watch(flag_end)

! --- DISP_SWITCH ---

! DISP_SWITCH = .true.
  DISP_SWITCH = (myrank==0)
  disp_switch_parallel = (myrank==0)

  if ( disp_switch ) then
#ifdef _DRSDFT_
     write(*,*) "DRSDFT(REAL8)"
#else
     write(*,*) "RSDFT(COMPLEX16)"
#endif
#ifdef _SPLINE_
     write(*,*) "SPLINE(ps_nloc2_module)"
#endif
  end if
     
! --- input parameters ---

  if (DISP_SWITCH) write(*,'(a60," read_param")') repeat("-",60)

  call read_parameters

! --- initial preparetaion ---

  call construct_aa
  call construct_bb(aa)

! --- RSMOL ---

  if ( SYStype == 1 ) then
     call read_rgrid_mol(myrank,2)
     call init_rgrid_mol( Ngrid(1),Hgrid(1),aa,bb,disp_switch )
  end if

! --- R-grid and G-grid ---

  call construct_rgrid(aa)
  call get_cutoff_ggrid
  call construct_NMGL_ggrid

  if ( DISP_SWITCH ) then
     write(*,*) "Gcut,Ecut=",Gcut,Ecut
     write(*,*) "NGgrid=",NGgrid
     write(*,*) "NMGL=",NMGL
     write(*,'(1x,"Hgrid(1:3)=",3f20.10)') Hgrid(1:3)
  end if

! --- Brillouin Zone sampling ---

  call generate_bz(disp_switch)

! --- initial set up for parallel computation ---

  call test_bcast

  call prep_0_scalapack(Nband,disp_switch)

  call init_parallel(disp_switch,Ngrid(1),Nband,Nbzsm,Nspin)

  call parallel_rgrid(node_partition(1:3),myrank_g)
  call parallel_ggrid(nprocs,myrank)

  call init_bcset(Md)

! --- parallel computation for RSMOL ---

  if ( SYStype == 1 ) then

     call mesh_div_1(np_grid,node_partition,Ngrid(1),pinfo_grid,disp_switch)

     id_grid(:)=pinfo_grid(7,:)
     ir_grid(:)=pinfo_grid(8,:)
     idisp(myrank)=id_grid(myrank_g)
     ircnt(myrank)=ir_grid(myrank_g)
     call mpi_allgather(idisp(myrank),1,mpi_integer,idisp,1 &
                       ,mpi_integer,mpi_comm_world,ierr)
     call mpi_allgather(ircnt(myrank),1,mpi_integer,ircnt,1 &
                       ,mpi_integer,mpi_comm_world,ierr)
     Ngrid(0)=sum(ir_grid)
     Igrid(1,0)=pinfo_grid(7,myrank_g)+1
     Igrid(2,0)=pinfo_grid(7,myrank_g)+pinfo_grid(8,myrank_g)
     Igrid(1,1)=pinfo_grid(1,myrank_g)+1
     Igrid(2,1)=pinfo_grid(1,myrank_g)+pinfo_grid(2,myrank)
     Igrid(1,2)=pinfo_grid(3,myrank_g)+1
     Igrid(2,2)=pinfo_grid(3,myrank_g)+pinfo_grid(4,myrank)
     Igrid(1,3)=pinfo_grid(5,myrank_g)+1
     Igrid(2,3)=pinfo_grid(5,myrank_g)+pinfo_grid(6,myrank)

     call init_bcset_mol(Md,Ngrid(1),np_grid,myrank_g,comm_grid,pinfo_grid)

  end if

! --- ESM esm ---

  if ( SYStype == 3 ) then

     call read_esm_rgrid(myrank,2)
     call prep_esm_rgrid(Md)
     call construct0_esm_rgrid

     id_grid(:)=0
     ir_grid(:)=0
     id_grid(myrank_g) = ML0_ESM-1
     ir_grid(myrank_g) = ML1_ESM-ML0_ESM+1
     call mpi_allgather(id_grid(myrank_g),1,mpi_integer,id_grid,1,mpi_integer,comm_grid,ierr)
     call mpi_allgather(ir_grid(myrank_g),1,mpi_integer,ir_grid,1,mpi_integer,comm_grid,ierr)
     if ( myrank == 0 ) then
        do i=0,np_grid-1
           write(*,*) i,id_grid(i),id_grid(i)+ir_grid(i)-1,ir_grid(i)
        end do
     end if
     idisp(:)=0
     ircnt(:)=0
     idisp(myrank)=id_grid(myrank_g)
     ircnt(myrank)=ir_grid(myrank_g)
     call mpi_allgather(idisp(myrank),1,mpi_integer,idisp,1,mpi_integer,comm_grid,ierr)
     call mpi_allgather(ircnt(myrank),1,mpi_integer,ircnt,1,mpi_integer,comm_grid,ierr)
     if ( myrank == 0 ) then
        do i=0,nprocs-1
           write(*,*) i,idisp(i)+1,idisp(i)+ircnt(i),ircnt(i)
        end do
     end if
     Ngrid(0) = ML_ESM
     Igrid(1,0) = id_grid(myrank_g)+1
     Igrid(2,0) = id_grid(myrank_g)+ir_grid(myrank_g)
     call flush(6)
     call mpi_barrier(mpi_comm_world,ierr)
     write(*,'(1x,i6,2x,8i8)') myrank,Igrid(:,:)
     call flush(6)

  end if

! --- array bounds ---

  call set_array_bound

! --- OpenMP parallel ---

  call init_omp(Igrid(1,1),Igrid(2,1),Igrid(1,2),Igrid(2,2) &
               ,Igrid(1,3),Igrid(2,3),ML_0,ML_1,disp_switch)

! --- kinetic energy oprator coefficients ---

  call get_coef_kinetic(aa,bb,MBZ,kbb,DISP_SWITCH,SYStype_in=SYStype)
  if ( SYStype == 1 ) call get_coef_kinetic_mol(Md)
  if ( SYStype == 3 ) call get_coef_kinetic_esm(aa,bb,MBZ,kbb,Md)

! --- Pseudopotential, initial density, and partial core correction ---

  select case(pselect)
  case default
     call read_pseudopot(myrank)
  case(4)
     call read_ps_gth(myrank)
  end select

  call count_electron

!----------------------- SOL sol -----

  if ( SYStype == 0 ) then

     call init_ps_local
     call init_ps_pcc
     call init_ps_initrho
     call watcht(disp_switch,"strf",0)
     call watcht(disp_switch,"strf",0)

     call construct_strfac !----- structure factor
     call watcht(disp_switch,"strf",1)
     call watcht(disp_switch,"strf",1)

     call construct_ps_local
     call watcht(disp_switch,"loc&pcc",1)
     call watcht(disp_switch,"loc",1)

     if ( pselect /= 4 ) then
        call construct_ps_pcc
        call watcht(disp_switch,"pcc",1)
        call construct_ps_initrho
        call normalize_density
     end if

     call destruct_strfac !----- structure factor

     if ( pselect /= 4 ) then
        call ps_nloc2_init(Gcut)
     end if
     call prep_ps_nloc2

!----------------------- ESM esm -----

  else if ( SYStype == 3 ) then

     call ps_nloc2_init(Gcut)
     call prep_ps_nloc2_esm

     call init_ps_local_rs
     call read_rshell(myrank,2)

     if ( allocated(Vion) ) deallocate(Vion)
     if ( allocated(rho) ) deallocate(rho)
     allocate( Vion(ML0_ESM:ML1_ESM)      ) ; Vion=0.d0
     allocate( rho(ML0_ESM:ML1_ESM,Nspin) ) ; rho=0.d0

     call construct_ps_local_rs(Vion)

     call construct_ps_initrho_rs(ML0_ESM,ML1_ESM,Nspin,rho)
     call normalize_density
!     c0=sum(rho)
!     call mpi_allreduce(c0,c,1,mpi_real8,mpi_sum,comm_grid,ierr)
!     rho=rho-c/ML_ESM+Nelectron/(ML_ESM*dV)
     write(*,*) "sum(rho)*dV",sum(rho)*dV,minval(rho),maxval(rho)

     call flush(6)

!----------------------- MOL mol -----

  else if ( SYStype == 1 ) then

     call init_ps_local_mol(Gcut)
     call init_ps_pcc_mol
     call init_ps_initrho_mol

     call construct_rgrid_mol
     call construct_ps_local_mol
     call construct_ps_pcc_mol
     call construct_ps_initrho_mol
     call normalize_density

     call ps_nloc2_init(Gcut)
     call prep_ps_nloc2_mol

     call construct_boundary_rgrid_mol(Md)

  end if

! if initrho is not available, random_number density is set here
  call init_density

!-------------------- BAND with SSEIG
#ifndef _DRSDFT_
  if ( iswitch_band == 2 ) then
     call init_localpot
     call read_localpot("vrho.dat1",myrank)
     call read_band(myrank,1)
     call band_sseig(disp_switch)
     goto 900
  end if
#endif
!--------------------

  call init_occ_electron
  call flush(6)

  if ( DISP_SWITCH ) then
     write(*,'(a60," main")') repeat("-",60)
     write(*,*) "Natom    =",Natom
     write(*,*) "Nelement =",Nelement
     write(*,*) "Nband =",Nband
     write(*,*) "Nspin =",Nspin
     write(*,*) "Nbzsm =",Nbzsm,MBZ
     write(*,*) "Nelectron =",Nelectron
     write(*,*) "Next_electron =",Next_electron
     write(*,*) "Ndspin,Nfixed =",Ndspin,Nfixed
     write(*,*) "Zps   =",Zps(1:Nelement)
     write(*,*) "sum(occ)=",sum(occ)
     if ( Nspin == 2 ) then
        write(*,*) "sum(occ(up))  =",sum(occ(:,:,1))
        write(*,*) "sum(occ(down))=",sum(occ(:,:,Nspin))
     endif
     do n=max(1,nint(Nelectron/2)-20),min(nint(Nelectron/2)+80,Nband)
        do k=1,Nbzsm
           write(*,*) n,k,(occ(n,k,s),s=1,Nspin)
        end do
     end do
  end if
  call flush(6)

! --- ESM esm ---

  if ( SYStype == 3 ) then

     call construct_ps_density_longloc
     call read_esm_genpot(myrank,2)
     allocate( vtmp(ML0_ESM:ML1_ESM) )
     vtmp=0.d0
     call esm_genpot(vtmp)
!     call func2gp_r_esm(10,ML0_ESM,ML1_ESM,vtmp)
!     goto 900
     Vion(:) = Vion(:) + vtmp(:)
     deallocate( vtmp )

  end if

! --- Ewald sum ---

  select case(SYStype)
  case default

     call watcht(disp_switch,"",0)
     call test_ewald(Eewald,disp_switch)
     call watcht(disp_switch,"test_ewald",1)
     call calc_ewald(Eewald,disp_switch)
     call watcht(disp_switch,"calc_ewald",1)

  case( 1 )

     call watcht(disp_switch,"",0)
     call calc_eion_mol(Eewald)
     call watcht(disp_switch,"eion_mol",1)
     if ( disp_switch ) write(*,*) "Ewld(MOL)=",Eewald

  end select 

! --- preparing for subspace diagonalization ---

  call prep_subspace_diag(Nband,disp_switch)

! --- Initial wave functions ---

  call init_wf

  do s=MSP_0,MSP_1
  do k=MBZ_0,MBZ_1
!     call gram_schmidt_m(1,Nband,k,s)
     call gram_schmidt_t(1,Nband,k,s)
  end do
  end do
!  call test_on_wf(myrank==0)

! --- Initial Potential ---

  call calc_hartree(ML_0,ML_1,MSP,rho,SYStype)

  call calc_xc

  call init_localpot

  do s=MSP_0,MSP_1
     Vloc(:,s) = Vion(:) + Vh(:) + Vxc(:,s)
  end do

! --- Read previous w.f. , density , potentials ---

  call watcht(disp_switch,"read",0)
  call read_data(disp_switch)
  call watcht(disp_switch,"read",1)

! ---

  call calc_with_rhoIN_total_energy(disp_switch)
  call calc_total_energy(.true.,disp_switch)

  if ( mod(imix,2) == 0 ) then
     call init_mixing(ML_1-ML_0+1,MSP_1-MSP_0+1, rho(ML_0,MSP_0))
  else
     call init_mixing(ML_1-ML_0+1,MSP_1-MSP_0+1,Vloc(ML_0,MSP_0))
  end if

  allocate( esp0(Nband,Nbzsm,Nspin) ) ; esp0=0.d0

  flag_exit = .false.
  flag_scf  = .false.

  do iter=1,Diter

     if ( disp_switch ) write(*,'(a40," iter=",i4)') repeat("-",40),iter

     if ( iter > Nsweep ) then
        if ( iswitch_scf == 1 ) then
           flag_scf = .true.
        else
           exit
        end if
     end if

     call watch(ct0,et0)

     esp0=esp
     do s=MSP_0,MSP_1
     do k=MBZ_0,MBZ_1
        call watcht(disp_switch,"",0)
        if ( iter == 1 .or. flag_scf ) then
!          call subspace_diag_la(k,s)
           call subspace_diag_sl(k,s,disp_switch)
        end if
        call watcht(disp_switch,"diag",1)
        call conjugate_gradient(ML_0,ML_1,Nband,k,s,Ncg,iswitch_gs &
                               ,unk(ML_0,1,k,s),esp(1,k,s),res(1,k,s))
        call watcht(disp_switch,"cg  ",1)
        call gram_schmidt_t(1,Nband,k,s)
        call watcht(disp_switch,"gs  ",1)
!       call subspace_diag_la(k,s)
        call subspace_diag_sl(k,s,disp_switch)
        call watcht(disp_switch,"diag",1)
     end do
     end do

     call esp_gather(Nband,Nbzsm,Nspin,esp)
     call calc_fermi(iter,Nfixed,Nband,Nbzsm,Nspin,Nelectron,Ndspin &
                    ,esp,weight_bz,occ,disp_switch)

     if ( disp_switch ) then
        write(*,'(a4,a6,a20,2a13,1x)') &
             "k","n","esp(n,k,s)","esp_err","occ(n,k,s)"
        do k=1,Nbzsm
        do n=max(1,nint(Nelectron/2)-20),min(nint(Nelectron/2)+80,Nband)
           write(*,'(i4,i6,2(f20.15,2g13.5,1x))') k,n &
           ,(esp(n,k,s),esp(n,k,s)-esp0(n,k,s),occ(n,k,s),s=1,Nspin)
        end do
        end do
        write(*,*) "sum(occ)=",(sum(occ(:,:,s)),s=1,Nspin)
        write(*,*) "flag_scf=",flag_scf
     end if

     call calc_with_rhoIN_total_energy(disp_switch)

     if ( flag_scf ) then
        call calc_density ! n_out
        call watcht(disp_switch,"hartree",0)
        call calc_hartree(ML_0,ML_1,MSP,rho)
        call watcht(disp_switch,"hartree",1)
        call calc_xc
        call calc_total_energy(.false.,disp_switch)
        if ( mod(imix,2) == 0 ) then
           call perform_mixing(ML_1-ML_0+1,MSP_1-MSP_0+1,rho(ML_0,MSP_0),flag_conv,disp_switch)
           call normalize_density
           m=(ML_1-ML_0+1)*(MSP_1-MSP_0+1)
           call mpi_allgather(rho(ML_0,MSP_0),m,mpi_real8,rho,m,mpi_real8,comm_spin,ierr)
           call watcht(disp_switch,"hartree",0)
           call calc_hartree(ML_0,ML_1,MSP,rho)
           call watcht(disp_switch,"hartree",1)
           call calc_xc
           do s=MSP_0,MSP_1
              Vloc(:,s) = Vion(:) + Vh(:) + Vxc(:,s)
           end do
        else if ( mod(imix,2) == 1 ) then
           do s=MSP_0,MSP_1
              Vloc(:,s) = Vion(:) + Vh(:) + Vxc(:,s)
           end do
           call perform_mixing(ML_1-ML_0+1,MSP_1-MSP_0+1,Vloc(ML_0,MSP_0),flag_conv,disp_switch)
        end if
     end if

     call watch(ct1,et1)
     if ( disp_switch ) write(*,*) "time(scf)",ct1-ct0,et1-et0
     call global_watch(flag_end)
     flag_exit = (flag_conv.or.flag_end.or.(iter==Diter))

     call watcht(disp_switch,"",0)
     call write_data(disp_switch,flag_exit)
     call watcht(disp_switch,"io",1)

     if ( flag_exit ) exit

  end do ! iter

  if ( disp_switch ) then
     write(*,*) "------------ SCF result ----------"
     write(*,'(a4,a6,a20,2a13,1x)') &
          "k","n","esp(n,k,s)","esp_err","occ(n,k,s)"
     do k=1,Nbzsm
     do n=1,Nband
        write(*,'(i4,i6,2(f20.15,2g13.5,1x))') k,n &
             ,(esp(n,k,s),esp(n,k,s)-esp0(n,k,s),occ(n,k,s),s=1,Nspin)
     end do
     end do
     write(*,*) "iter,sqerr=",iter,sqerr_out(1:Nspin)
     rewind 98
     write(98,'(a4,a6,a20,2a13,1x)') &
          "k","n","esp(n,k,s)","esp_err","occ(n,k,s)"
     do k=1,Nbzsm
     do n=1,Nband
        write(98,'(i4,i6,2(f20.15,2g13.5,1x))') k,n &
             ,(esp(n,k,s),esp(n,k,s)-esp0(n,k,s),occ(n,k,s),s=1,Nspin)
     end do
     end do
  end if

  call calc_total_energy(.true.,disp_switch)

  m=Ngrid(1)/2
  if ( .not.allocated(LL_ESM) ) then
     ML0_ESM=ML_0
     ML1_ESM=ML_1
     allocate( LL_ESM(3,ML_0:ML_1) ) ; LL_ESM=0
     i=ML_0-1
     do i3=Igrid(1,3),Igrid(2,3)
     do i2=Igrid(1,2),Igrid(2,2)
     do i1=Igrid(1,1),Igrid(2,1)
        i=i+1
        LL_ESM(1,i)=i1
        LL_ESM(2,i)=i2
        LL_ESM(3,i)=i3
     end do
     end do
     end do
     m=0
  end if

!  call func2gp_c_esm(10,ML0_ESM,ML1_ESM,unk(:,1,1,1))
!  call func2gp_r_esm(11,ML0_ESM,ML1_ESM,Vloc(:,1))
!  call func2gp_r_esm(12,ML0_ESM,ML1_ESM,Vion)
!  call func2gp_r_esm(13,ML0_ESM,ML1_ESM,Vh)
!  call func2gp_r_esm(14,ML0_ESM,ML1_ESM,Vxc(:,1))
!  call func2gp_r_esm(15,ML0_ESM,ML1_ESM,rho(:,1))
!  goto 900

  if ( flag_end ) then
     if ( disp_switch ) write(*,*) "flag_end=",flag_end
     call end_mpi_parallel
     stop
  end if

  if ( disp_switch ) write(*,'(a40," result")') repeat("-",40)

  if ( flag_scf ) then
     call calc_density
     call calc_hartree(ML_0,ML_1,MSP,rho)
     call calc_xc
     do s=MSP_0,MSP_1
        Vloc(:,s) = Vion(:) + Vh(:) + Vxc(:,s)
     end do
  end if

  call calc_total_energy(.true.,disp_switch)


! --- force calculation ---

  if ( pselect /= 4 ) then
     call ps_nloc2_init_derivative
  end if

  if ( iswitch_opt == -1 ) then

     allocate( force(3,Natom) ) ; force=0.d0
     allocate( forcet(3,Natom) ) ; forcet=0.d0

     call watcht(disp_switch,"floc",0)
     call calc_force_ps_local(Natom,force)
     call watcht(disp_switch,"floc",1)
     forcet(:,:)=forcet(:,:)+force(:,:)

     if ( disp_switch ) then
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
        end do
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,forcet(1:3,i),myrank
        end do
     end if

     call watcht(disp_switch,"fewl",0)
     call calc_force_ewald(Natom,force)
     call watcht(disp_switch,"fewl",1)
     if ( disp_switch ) then
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
        end do
     end if
     forcet(:,:)=forcet(:,:)+force(:,:)

     if ( disp_switch ) then
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
        end do
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,forcet(1:3,i),myrank
        end do
     end if

     call watch(ct0,et0)
     call calc_force_ps_nloc2(Natom,force)
     call watch(ct1,et1) ; if (disp_switch) write(*,*) "fnlc:",ct1-ct0,et1-et0
     forcet(:,:)=forcet(:,:)+force(:,:)

     if ( disp_switch ) then
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,force(1:3,i),myrank
        end do
     end if

     if ( disp_switch ) then
        write(*,*) "ftot"
        do i=1,Natom
           write(*,'(1x,i6,3g20.10,i6)') i,forcet(1:3,i),myrank
        end do
     end if

  end if

! --- BAND ---
#ifndef _DRSDFT_
  if ( iswitch_band == 1 ) then
     call read_band(myrank,1)
     call band(nint(Nelectron*0.5d0),disp_switch)
  end if
#endif

  select case(iswitch_opt)
  case( 1,2 )
     call atomopt(iswitch_opt,disp_switch)
  case( 3 )
#ifdef _DRSDFT_
! --- CPMD ---
     call bomd
#else
     write(*,*) "RS-CPMD is not available for COMPLEX16"
     write(*,*) "Please re-compile the program"
#endif
  end select

! --- finalize ---

  if ( DISP_SWITCH ) then
     write(*,*) "END_PROGRAM : MAIN" 
  end if
900 continue
  call end_mpi_parallel

END PROGRAM Real_Space_Solid
