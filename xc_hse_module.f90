MODULE xc_hse_module

  use aa_module
  use bb_module
  use rgrid_module
  use array_bound_module
  use kinetic_module, only: SYStype
  use kinetic_variables, only: Md
  use density_module, only: rho
  use electron_module, only: Nspin
  use parallel_module
  use ps_pcc_module
  use bc_module
  use xc_hybrid_module
  use wf_module
  use bz_module
  use fd_module
  use expint_module
  use rsdft_mpi_module
  use fock_fft_module
  use watch_module

  implicit none

  PRIVATE
  PUBLIC :: calc_xc_hse

  real(8) :: E_exchange_pbe
  real(8) :: E_exchange_pbe_sr
  real(8) :: E_exchange
  real(8) :: E_correlation

  real(8),allocatable :: nab(:)

  logical :: flag_firsttime = .true.

CONTAINS

  SUBROUTINE calc_xc_hse(n1,n2,n3,Vxc,Exc,E_exchange_exx)
    implicit none
    integer,intent(IN) :: n1,n2,n3
    real(8),intent(OUT) :: Vxc(n1:n2,n3),Exc,E_exchange_exx
#ifdef _DRSDFT_
    Vxc=0.0d0
    Exc=0.0d0
    E_exchange_exx=0.0d0
#else
    real(8),parameter :: mu=0.21951d0,Kp=0.804d0
    real(8),parameter :: ep=1.d-25
    real(8),parameter :: A00  =0.031091d0,A01  =0.015545d0,A02  =0.016887d0
    real(8),parameter :: alp10=0.21370d0 ,alp11=0.20548d0 ,alp12=0.11125d0
    real(8),parameter :: bt10 =7.5957d0  ,bt11 =1.41189d1 ,bt12 =1.0357d1
    real(8),parameter :: bt20 =3.5876d0  ,bt21 =6.1977d0  ,bt22 =3.6231d0
    real(8),parameter :: bt30 =1.6382d0  ,bt31 =3.3662d0  ,bt32 =0.88026d0
    real(8),parameter :: bt40 =0.49294d0 ,bt41 =0.62517d0 ,bt42 =0.49671d0
    real(8),parameter :: C1=2.14611945579107d0,C2=0.031091d0
    complex(8),parameter :: zero=(0.0d0,0.0d0)
    integer :: i,j,i1,i2,i3,j1,j2,j3,k1,k2,k3,m,ispin,ierr,itmp,tr
    integer :: s,k,q,n,ML0,MB_switch
    integer :: irank_b,irank_k,irank_s,mrnk,icount_b,icount_k,icount_s
    integer :: Mx,My,Mz,ML1,ML2,ML3
    real(8),allocatable :: wtmp(:,:,:),wrho(:,:,:),rtmp(:),gx(:),gy(:),gz(:)
    real(8) :: ctime0,ctime1,etime0,etime1,mem,memax
    real(8) :: g1,g2,g3,b(3,3),sbf(4),rbf(4),k_fock(3),q_fock(3)
    real(8) :: trho,kf,ec_lda,ex_lda,vx_lda,T,Fx
    real(8) :: Hs,A,Ai,dH_dT,dA_dn,dec_dn,dH_dA,rs,tmp,tmp1,tmp2
    real(8) :: ec_U,ec_P,deU_dn,deP_dn,alpc,dac_dn,phi,dphi_dz
    real(8) :: dH_dphi,fz,dfz_dz,dec_dz,const1,const2,srho(2),dz_dn(2)
    real(8) :: srpi,w1,w2,w3,w4,w5,w6,w7,w8,drdw,erb,s1,s2,s3,s4,s5,s6
    real(8),parameter :: er1=-1.128223946706117d0,er2=1.452736265762971d0
    real(8),parameter :: er3=-1.243162299390327d0,er4=0.971824836115601d0
    real(8),parameter :: er5=-0.568861079687373d0,er6=0.246880514820192d0
    real(8),parameter :: er7=-0.065032363850763d0,er8=0.008401793031216d0
    real(8),parameter :: Ah=1.0161144d0,Bh=-0.37170836d0,Ch=-0.077215461d0
    real(8),parameter :: Dh=0.57786348d0,Eh=-0.051955731d0
    real(8),parameter :: Hc1=0.00979681d0,Hc2=0.0410834d0,Hc3=0.187440d0
    real(8),parameter :: Hc4=0.00120824d0,Hc5=0.0347188d0
    real(8),parameter :: Fc1=6.4753871d0,Fc2=0.47965830d0
    real(8),parameter :: EGc1=-0.02628417880d0,EGc2=-0.07117647788d0
    real(8),parameter :: EGc3=0.08534541323d0
    real(8),parameter :: exp_ei1=4.03640d0,exp_ei2=1.15198d0
    real(8),parameter :: exp_ei3=5.03627d0,exp_ei4=4.19160d0
    real(8),parameter :: EGscut=0.08d0,wcut=14.d0,erfc_cut=700.d0
    real(8) :: Fh,Hh,Ga,Gb,EG,dsdF,dsdH,dsdGa,dsdGb,dsdEG
    real(8) :: DHs,DHs2,DHs3,DHs4,DHs72,DHs92,dsdDHs
    real(8) :: DHsbw,DHsbw2,DHsbw3,DHsbw4,DHsbw5
    real(8) :: DHsbw12,DHsbw32,DHsbw52,DHsbw72,DHsbw92
    real(8) :: DHsw,DHsw2,DHsw52,DHsw72,drdDHsw
    real(8) :: Hsbw,Hsbw2,Hsbw3,Hsbw4
    real(8) :: Hsbw12,Hsbw32,Hsbw52,Hsbw72,dsdHsbw,drdHsbw
    real(8) :: HsbwA94,HsbwA942,HsbwA943,HsbwA945,HsbwA9412
    real(8) :: exp_erf,exp_ei,dsdexp_erf,dsdexp_ei,drdexp_erf,drdexp_ei
    real(8) :: Tm2,Tm3,Tm4,Tm5,dsdTm2,dsdTm3,dsdTm4,dsdTm5,drdTm3,drdTm4,drdTm5
    real(8) :: Tm1,dsdTm1,drdTm1,t10,dsdt10,drdt10
    real(8) :: t1,dsdt1,drdt1,t2t9,dsdt2t9,drdt2t9
    real(8) :: Fx_hse,dsdfx,drdfx
    real(8) :: A2,A3,A4,A12,A32,A52,A72,rp1,rp2,drdrp1,drdrp2
    real(8) :: f2,f3,f4,f5,f6,f7,f8,f9
    real(8) :: dsdf2,dsdf3,dsdf4,dsdf5,dsdf6,dsdf7,dsdf8,dsdf9
    real(8) :: drdf2,drdf3,drdf4,drdf5,drdf6,drdf7,drdf8,drdf9
    real(8),allocatable :: rtmp_sr(:)
    real(8) :: c,sum0,sum1
    real(8),allocatable :: rrrr(:,:),rho_tmp(:),zeta(:)
    real(8),parameter :: small_hse=0.d0
    integer :: a1b,b1b,a2b,b2b,a3b,b3b
#ifdef _DRSDFT_
    real(8),allocatable :: trho_hf(:),tvht(:)
#else
    complex(8),allocatable :: trho_hf(:),tvht(:)
#endif            
    logical :: flag_alloc
    logical :: DISP_SWITCH_TMP
    real(8) :: aaL(3),PI,H1,H2,H3,ctfft,etfft,ct0,ct1,et0,et1
    integer,allocatable :: LLL2(:,:,:)
    real(8) :: ctt0,ctt1,ctt2,ctt3,ett0,ett1,ett2,ett3

    INTERFACE
       FUNCTION bberf(x)
         real(8) :: bberf,x
       END FUNCTION bberf
    END INTERFACE

    call watch(ctime0,etime0)
         
    ML0 = n2-n1+1
    ML1 = Ngrid(1)
    ML2 = Ngrid(2)
    ML3 = Ngrid(3)

    a1b = Igrid(1,1)
    b1b = Igrid(2,1)
    a2b = Igrid(1,2)
    b2b = Igrid(2,2)
    a3b = Igrid(1,3)
    b3b = Igrid(2,3)
      
    E_exchange_pbe=0.d0
    E_exchange_pbe_sr=0.d0
    E_exchange_exx=0.d0
    E_exchange=0.d0
    E_correlation=0.d0
    Exc=0.d0
    Vxc(:,:)=0.d0
    flag_alloc=.false.
    Mx=ML1+Md
    My=ML2+Md
    Mz=ML3+Md

    PI = acos(-1.0d0)
    H1 = Hgrid(1)
    H2 = Hgrid(2)
    H3 = Hgrid(3)

    aaL(1) = sqrt( sum(aa(1:3,1)**2) )
    aaL(2) = sqrt( sum(aa(1:3,2)**2) )
    aaL(3) = sqrt( sum(aa(1:3,3)**2) )

    b(:,:)=0.d0 
    b(1:3,1)=aaL(1)*bb(1:3,1)/(2.d0*Pi)/H1
    b(1:3,2)=aaL(2)*bb(1:3,2)/(2.d0*Pi)/H2
    b(1:3,3)=aaL(3)*bb(1:3,3)/(2.d0*Pi)/H3

    if ( flag_firsttime ) then
       flag_firsttime = .false.
       allocate( nab(-Md:Md) ) ; nab=0.0d0
       call get_coef_nabla_fd(Md,nab)
       call read_xc_hybrid(myrank,1)
       allocate( VFunk(ML_0:ML_1,MB,MBZ,MSP)  ) ; VFunk=(0.0d0,0.0d0)
       allocate( unk_hf(ML_0:ML_1,MB,MBZ,MSP) ) ; unk_hf=(0.0d0,0.0d0)
       if ( MBZ == 1 ) then
          tr_switch  = 0
          occ_factor = 0.5d0
       else
          tr_switch  = 1
          occ_factor = 0.25d0
       end if
       if ( DISP_SWITCH_PARALLEL ) write(*,*) "occ_factor",occ_factor
    end if

    if ( icount_sweep_hybrid <= Nsweep_hybrid ) return

    iflag_hse = 2
    if ( DISP_SWITCH_PARALLEL ) write(*,*) "iflag_hse=",iflag_hse

    call update_xc_hybrid(MB_0,MB_1,MBZ_0,MSP_0,unk)

! negative value check >>>>>>>>>>
    sbf(1:3)=0.d0
    do ispin=1,MSP
       do i=n1,n2
          if ( rho(i,ispin) < 0.d0 ) sbf(ispin)=sbf(ispin)+rho(i,ispin)
       end do
    end do
    if ( flag_pcc_0 ) then
       do i=n1,n2
          if ( rhoc(i) < 0.d0 ) sbf(3)=sbf(3)+rhoc(i)
       end do
    end if
    call mpi_allreduce(sbf,rbf,3,MPI_REAL8,MPI_SUM,comm_grid,ierr)
    if ( DISP_SWITCH_PARALLEL ) then
       write(*,'(1x,"negative charge =",3g20.10)') rbf(1:3)*dV
    end if
! <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

    j1=Ngrid(1)-1+Md
    j2=Ngrid(2)-1+Md
    j3=Ngrid(3)-1+Md
    allocate( LLL2(-Md:j1,-Md:j2,-Md:j3) ) ; LLL2=0

    call Make_GridMap(LLL2)

    allocate( rrrr(ML,3)     ) ; rrrr=0.d0
    allocate( gx(n1:n2)      ) ; gx=0.d0
    allocate( gy(n1:n2)      ) ; gy=0.d0
    allocate( gz(n1:n2)      ) ; gz=0.d0
    allocate( rtmp(n1:n2)    ) ; rtmp=0.d0
    allocate( rtmp_sr(n1:n2) ) ; rtmp_sr=0.d0
    allocate( rho_tmp(n1:n2) ) ; rho_tmp=0.d0
    allocate( zeta(n1:n2)    ) ; zeta=0.d0

    rho_tmp(:)=0.0d0
    do ispin=1,MSP
       rho_tmp(n1:n2)=rho_tmp(n1:n2)+rho(n1:n2,ispin)
    end do
    if ( flag_pcc_0 ) then
       rho_tmp(n1:n2)=rho_tmp(n1:n2)+rhoc(n1:n2)
    end if
    where( rho_tmp < 0.d0 )
       rho_tmp=0.d0
    end where
    zeta(n1:n2)=rho(n1:n2,1)-rho(n1:n2,Nspin)
    j=0
    do i=n1,n2
       if ( rho_tmp(i)==0.d0 ) then
          zeta(i)=0.d0
       else
          zeta(i)=zeta(i)/rho_tmp(i)
       end if
       if ( zeta(i) > 1.d0 .or. zeta(i) < -1.d0 ) then
          j=j+1
          if ( DISP_SWITCH_PARALLEL ) write(*,*) j,zeta(i),rho(i,1:nspin)
       end if
    end do
    where( zeta >  1.d0 )
       zeta= 1.d0
    end where
    where( zeta < -1.d0 )
       zeta=-1.d0
    end where

    www(:,:,:,:)=(0.0d0,0.0d0)
    select case(SYStype)
    case default
       i=n1-1
       do i3=a3b,b3b
       do i2=a2b,b2b
       do i1=a1b,b1b
          i=i+1
          www(i1,i2,i3,1)=rho_tmp(i)
       end do
       end do
       end do
    case(1,2)
!       do i=n1,n2
!          www(LL2(1,i),LL2(2,i),LL2(3,i),1)=rho_tmp(i)
!       end do
    end select

    call bcset(1,1,Md,0)

    select case(SYStype)
    case default
       i=n1-1
       do i3=a3b,b3b
       do i2=a2b,b2b
       do i1=a1b,b1b
          i=i+1
          g1=0.d0 ; g2=0.d0 ; g3=0.d0
          do m=1,Md
             g1=g1-nab(m)*(www(i1-m,i2,i3,1)-www(i1+m,i2,i3,1))
             g2=g2-nab(m)*(www(i1,i2-m,i3,1)-www(i1,i2+m,i3,1))
             g3=g3-nab(m)*(www(i1,i2,i3-m,1)-www(i1,i2,i3+m,1))
          end do
          gx(i)=b(1,1)*g1+b(1,2)*g2+b(1,3)*g3
          gy(i)=b(2,1)*g1+b(2,2)*g2+b(2,3)*g3
          gz(i)=b(3,1)*g1+b(3,2)*g2+b(3,3)*g3
       end do
       end do
       end do
    case(1,2)
!       do i=n1,n2
!          i1=LL2(1,i) ; i2=LL2(2,i) ; i3=LL2(3,i)
!          g1=0.d0 ; g2=0.d0 ; g3=0.d0
!          do m=1,Md
!             g1=g1-nab(m)*(www(i1-m,i2,i3,1)-www(i1+m,i2,i3,1))
!             g2=g2-nab(m)*(www(i1,i2-m,i3,1)-www(i1,i2+m,i3,1))
!             g3=g3-nab(m)*(www(i1,i2,i3-m,1)-www(i1,i2,i3+m,1))
!          end do
!          gx(i)=b(1,1)*g1+b(1,2)*g2+b(1,3)*g3
!          gy(i)=b(2,1)*g1+b(2,2)*g2+b(2,3)*g3
!          gz(i)=b(3,1)*g1+b(3,2)*g2+b(3,3)*g3
!       end do
    end select

!
! --- PBE Exchange ---
!

    do ispin=MSP_0,MSP_1

       do i=n1,n2

          trho=dble(nspin)*rho(i,ispin)
          if ( allocated(rhoc) ) trho=trho+rhoc(i)

          if ( trho <= small_hse ) cycle

          kf=(3.d0*Pi*Pi*trho)**(1.d0/3.d0)

          ex_lda=-3.d0/(4.d0*Pi)*kf
          vx_lda=-1.d0/Pi*kf

          g2=gx(i)*gx(i)+gy(i)*gy(i)+gz(i)*gz(i)

          Fx=1.d0+Kp-4.d0*Kp*Kp*(trho*kf)**2/(4.d0*Kp*(trho*kf)**2+mu*g2)

          E_exchange_pbe=E_exchange_pbe+trho*ex_lda*Fx

!
! --- Short Range PBE Exchange ---
!

! --- Screened Parameter ---

          srpi = sqrt(Pi) 
          w1   = omega/kf
          drdw =-w1/(3.d0*trho)

          if ( w1 <= wcut ) then
             erb=1.455915450052607d0
          else
             erb=2.d0
          end if

          w2=w1*w1
          w3=w2*w1
          w4=w3*w1
          w5=w4*w1
          w6=w5*w1
          w7=w6*w1
          w8=w7*w1
               
! --- Enforced Lieb-Oxford Bound ---

          s2=g2/(4.d0*(trho*kf)**2.d0)
          s1=sqrt(s2)
          if ( s1 > 8.3d0 ) then
             s1=8.572844d0-18.796223d0/s2
             s2=s1*s1
          end if

          s3=s2*s1
          s4=s3*s1
          s5=s4*s1
          s6=s5*s1

! --- Calculate H(s), F(s), and EG(s) Functions for PBE Exchange Hole ---

          Hh  =(Hc1*s2+Hc2*s4)/(1.d0+Hc3*s4+Hc4*s5+Hc5*s6)
          dsdH=((2.d0*Hc1*s1+4.d0*Hc2*s3)*(1.d0+Hc3*s4+Hc4*s5+Hc5*s6) &
     &         -(Hc1*s2+Hc2*s4)*(4.d0*Hc3*s3+5.d0*Hc4*s4+6.d0*Hc5*s5)) &
     &            /(1.d0+Hc3*s4+Hc4*s5+Hc5*s6)**2.d0

          Fh  =Fc1*Hh+Fc2
          dsdF=Fc1*dsdH

          DHs   =Dh+Hh*s2
          DHs2  =DHs*DHs
          DHs3  =DHs2*DHs
          DHs4  =DHs3*DHs
          DHs72 =DHs3*sqrt(DHs)
          DHs92 =DHs72*DHs
          dsdDHs=2.d0*s1*Hh+dsdH*s2

          DHsbw  =Dh+s2*Hh+erb*w2
          DHsbw2 =DHsbw*DHsbw
          DHsbw3 =DHsbw2*DHsbw
          DHsbw4 =DHsbw3*DHsbw
          DHsbw5 =DHsbw4*DHsbw
          DHsbw12=sqrt(DHsbw)
          DHsbw32=DHsbw12*DHsbw
          DHsbw52=DHsbw32*DHsbw
          DHsbw72=DHsbw52*DHsbw
          DHsbw92=DHsbw72*DHsbw

          DHsw   =DHs+w2
          DHsw2  =DHsw*DHsw
          DHsw52 =DHsw2*sqrt(DHsw)
          DHsw72 =DHsw52*DHsw
          drdDHsw=2.d0*w1*drdw

          Hsbw   =s2*Hh+erb*w2
          Hsbw2  =Hsbw*Hsbw
          Hsbw3  =Hsbw2*Hsbw
          Hsbw4  =Hsbw3*Hsbw
          Hsbw12 =sqrt(Hsbw)
          Hsbw32 =Hsbw12*Hsbw
          Hsbw52 =Hsbw32*Hsbw
          Hsbw72 =Hsbw52*Hsbw
          dsdHsbw=dsdH*s2+2.d0*s1*Hh
          drdHsbw=2.d0*erb*drdw*w1

          HsbwA94  =2.25d0*Hsbw/Ah
          HsbwA942 =HsbwA94*HsbwA94
          HsbwA943 =HsbwA942*HsbwA94
          HsbwA945 =HsbwA943*HsbwA942
          HsbwA9412=sqrt(HsbwA94)

          A2 =Ah*Ah
          A3 =A2*Ah
          A4 =A3*Ah
          A12=sqrt(Ah)
          A32=A12*Ah
          A52=A32*Ah
          A72=A52*Ah

          if ( s1 > EGscut ) then
             Ga   =srpi*(15.d0*Eh+6.d0*Ch*(1.d0+Fh*s2)*DHs+4.d0*Bh*DHs2+8.d0*Ah*DHs3)/(16.d0*DHs72) &
     &                  -0.75d0*Pi*A12*exp(2.25d0*Hh*s2/Ah)*(1.d0-bberf(1.5d0*s1*sqrt(Hh/Ah)))
             dsdGa=1.d0/32.d0*srpi*((36.d0*(2.d0*Hh+dsdH*s1)/sqrt(Hh)) &
     &               +(-8.d0*Ah*dsdDHs*DHs3-105.d0*dsdDHs*Eh-30.d0*Ch*dsdDHs*DHs*(1.d0+s2*Fh) &
     &                 +12.d0*DHs2*(-Bh*dsdDHs+Ch*s1*(dsdF*s1+2.d0*Fh)))/DHs92 &
     &               -(54.d0*exp(2.25d0*Hh*s2/Ah)*srpi*s1*(2.d0*Hh+dsdH*s1)*(1.d0-bberf(1.5d0*sqrt(Hh/Ah)*s1)))/A12)

             Gb   =15.d0/16.d0*srpi*s2/DHs72
             dsdGb=15.d0*srpi*s1*(4.d0*DHs-7.d0*dsdDHs*s1)/(32.d0*DHs92)

             EG   =-(0.75d0*Pi+Ga)/Gb
             dsdEG=(-4.d0*dsdGa*Gb+dsdGb*(4.d0*Ga+3.d0*Pi))/(4.d0*Gb*Gb)
          else
             EG   =EGc1+EGc2*s2+EGc3*s4
             dsdEG=2.d0*EGc2*s1+4.d0*EGc3*s3
          end if
      
! --- Calculate the Terms for HSE Enhancement Factor ---

          Tm2   =(DHs2*Bh+DHs*Ch+2.d0*Eh+DHs*s2*Ch*Fh+2.d0*s2*EG)/(2.d0*DHs3)
          dsdTm2=(-6.d0*dsdDHs*(EG*s2+Eh)+DHs2*(-dsdDHs*Bh+s1*Ch*(dsdF*s1+2.d0*Fh)) &
     &                +2.d0*DHs*(2.d0*EG*s1-dsdDHs*Ch+s2*(dsdEG-dsdDHs*Ch*Fh)))/(2.d0*DHs4)

          Tm3   =-w1*(4.d0*DHsw2*Bh+6.d0*DHsw*Ch+15.d0*Eh+6.d0*DHsw*s2*Ch*Fh+15.d0*s2*EG)/(8.d0*DHs*DHsw52)
          dsdTm3=w1*(2.d0*dsdDHs*DHsw*(4.d0*DHsw2*Bh+6.d0*DHsw*Ch+15.d0*Eh+3.d0*s2*(5.d0*EG+2.d0*DHsw*Ch*Fh)) &
     &                +DHs*(75.d0*dsdDHs*(EG*s2+Eh)+4.d0*DHsw2*(dsdDHs*Bh-3.d0*s1*Ch*(dsdF*s1+2.d0*Fh)) &
     &                -6.d0*DHsw*(-3.d0*dsdDHs*Ch+s1*(10.d0*EG+5.d0*dsdEG*s1-3.d0*dsdDHs*s1*Ch*Fh))))/(16.d0*DHs2*DHsw72)
          drdTm3=(-2.d0*drdw*DHsw*(4.d0*DHsw2*Bh+6.d0*DHsw*Ch+15.d0*Eh+3.d0*s2*(5.d0*EG+2.d0*DHsw*Ch*Fh)) &
     &                +w1*drdDHsw*(75.d0*(EG*s2+Eh)+2.d0*DHsw*(2.d0*DHsw*Bh+9.d0*Ch+9.d0*s2*Ch*Fh)))/(16.d0*DHs*DHsw72)

          Tm4   =-w3*(DHsw*Ch+5.d0*Eh+DHsw*s2*Ch*Fh+5.d0*s2*EG)/(2.d0*DHs2*DHsw52)
          dsdTm4=(w3*(4.d0*dsdDHs*DHsw*(DHsw*Ch+5.d0*Eh+s2*(5.d0*EG+DHsw*Ch*Fh))+DHs*(25.d0*dsdDHs*(EG*s2+Eh) &
     &                -2.d0*DHsw2*s1*Ch*(dsdF*s1+2.d0*Fh)+DHsw*(3.d0*dsdDHs*Ch+s1*(-20.d0*EG-10.d0*dsdEG*s1 &
     &                +3.d0*dsdDHs*s1*Ch*Fh)))))/(4.d0*DHs3*DHsw72)
          drdTm4=(w2*(-6.d0*drdw*DHsw*(DHsw*Ch+5.d0*Eh+s2*(5.d0*EG+DHsw*Ch*Fh))+w1*drdDHsw*(25.d0*(EG*s2+Eh) &
     &                +3.d0*DHsw*Ch*(1.d0+s2*Fh))))/(4.d0*DHs2*DHsw72)
               
          Tm5   =-w5*(Eh+s2*EG)/(DHs3*DHsw52)
          dsdTm5=(w5*(6.d0*dsdDHs*DHsw*(EG*s2+Eh)+DHs*(-2.d0*DHsw*s1*(2.d0*EG+dsdEG*s1) &
     &                +5.d0*dsdDHs*(EG*s2+Eh))))/(2.d0*DHs4*DHsw72)
          drdTm5=(w4*5.d0*(EG*s2+Eh)*(-2.d0*drdw*DHsw+drdDHsw*w1))/(2.d0*DHs3*DHsw72)
       
          if ( HsbwA94 < erfc_cut ) then
             exp_erf=Pi*exp(HsbwA94)*(1.d0-bberf(HsbwA9412))
             exp_ei =exp(HsbwA94)*(-expint(1,HsbwA94))
          else
             exp_erf=Pi*(1.d0/(srpi*HsbwA9412)-1.d0/(2.d0*sqrt(Pi*HsbwA943))+3.d0/(4.d0*sqrt(Pi*HsbwA945)))
             exp_ei =-(1.d0/HsbwA94)*(HsbwA942+exp_ei1*HsbwA94+exp_ei2)/(HsbwA942+exp_ei3*HsbwA94+exp_ei4)
          end if

          dsdexp_erf=dsdHsbw*(-(3.d0*srpi*sqrt(Hsbw/Ah))/(2.d0*Hsbw)+(9.d0*exp_erf)/(4.d0*Ah))
          drdexp_erf=drdHsbw*(-(3.d0*srpi*sqrt(Hsbw/Ah))/(2.d0*Hsbw)+(9.d0*exp_erf)/(4.d0*Ah))

          dsdexp_ei =dsdHsbw*(0.25d0*(4.d0/Hsbw+(9.d0*exp_ei)/Ah))
          drdexp_ei =drdHsbw*(0.25d0*(4.d0/Hsbw+(9.d0*exp_ei)/Ah))

! --- Calculate HSE Enhancement Factor ---

          if ( s1 > 0.0d0 .or. w1 > 0.0d0 ) then
             t10   =0.5d0*Ah*Log(Hsbw/DHsbw)
             dsdt10=0.5d0*Ah*dsdHsbw*(1.d0/Hsbw-1.d0/DHsbw)
             drdt10=0.5d0*Ah*drdHsbw*(1.d0/Hsbw-1.d0/DHsbw)
          end if

          if ( w1 == 0.d0 ) then

             t1   =-0.5d0*Ah*exp_ei
             dsdt1=-0.5d0*Ah*dsdexp_ei
             drdt1=-0.5d0*Ah*drdexp_ei
             if ( s1 > 0.d0 ) then
                Tm1   =t1+t10
                dsdTm1=dsdt1+dsdt10
                drdTm1=drdt1+drdt10

                Fx_hse=-8.d0/9.d0*(Tm1+Tm2)
                dsdfx =-8.d0/9.d0*(dsdTm1+dsdTm2)
                drdfx =-8.d0/9.d0*drdTm1
             else
                Fx_hse=1.d0
                dsdfx =0.d0
                drdfx =0.d0
             end if

          else if ( w1 > wcut ) then

             Tm1   =-0.5d0*Ah*(exp_ei+log(DHsbw)-log(Hsbw))
             dsdTm1=dsdHsbw*(-Ah/(2.d0*DHsbw)-1.125d0*exp_ei)
             drdTm1=drdHsbw*(-Ah/(2.d0*DHsbw)-1.125d0*exp_ei)

             Fx_hse=-8.d0/9.d0*(Tm1+Tm2+Tm3+Tm4+Tm5)
             dsdfx =-8.d0/9.d0*(dsdTm1+dsdTm2+dsdTm3+dsdTm4+dsdTm5)
             drdfx =-8.d0/9.d0*(drdTm1+drdTm3+drdTm4+drdTm5)

          else 

! --- Calculate Polynomials using Approximated Complementary Error Functions ---

             rp1   =-1.5d0*er1*A12*w1+27.d0*er3*w3/(8.d0*A12)-243.d0*er5*w5/(32.d0*A32)+2187.d0*er7*w7/(128.d0*A52)
             drdrp1=-1.5d0*er1*drdw*A12+(81.d0*er3*drdw*w2)/(8.d0*A12)-(1215.d0*er5*drdw*w4)/(32.d0*A32) &
     &                    +(15309.d0*er7*drdw*w6)/(128.d0*A52)

             rp2   =-Ah+2.25d0*er2*w2-81.d0*er4*w4/(16.d0*Ah)+729.d0*er6*w6/(64.d0*A2)-6561.d0*er8*w8/(256.d0*A3)
             drdrp2=0.5d0*(9.d0*er2*drdw*w1)-(81.d0*er4*drdw*w3)/(4.d0*Ah) &
                  +(2187.d0*er6*drdw*w5)/(32.d0*A2)-(6561.d0*er8*drdw*w7)/(32.d0*A3)
                  
             t1   =0.5d0*(rp1*exp_erf+rp2*exp_ei)
             dsdt1=0.5d0*(dsdexp_erf*rp1+dsdexp_ei*rp2)
             drdt1=0.5d0*(drdrp2*exp_ei+drdexp_erf*rp1+drdexp_ei*rp2+drdrp1*exp_erf) 

             f2   =0.5d0*er1*srpi*Ah/DHsbw12
             dsdf2=dsdHsbw*(-er1*srpi*Ah/(4.d0*DHsbw32))
             drdf2=drdHsbw*(-er1*srpi*Ah/(4.d0*DHsbw32))

             f3   =0.5d0*er2*Ah/DHsbw
             dsdf3=dsdHsbw*(-er2*Ah/(2.d0*DHsbw2))
             drdf3=drdHsbw*(-er2*Ah/(2.d0*DHsbw2))

             f4   =er3*srpi*(-1.125d0/Hsbw12+0.25d0*Ah/DHsbw32)
             dsdf4=dsdHsbw*er3*srpi*((9.d0/(16.d0*Hsbw32))-(3.d0*Ah/(8.d0*DHsbw52)))
             drdf4=drdHsbw*er3*srpi*((9.d0/(16.d0*Hsbw32))-(3.d0*Ah/(8.d0*DHsbw52)))

             f5   =er4*(1.d0/128.d0)*(-144.d0*(1.d0/Hsbw)+64.d0*(1.d0/DHsbw2)*Ah)
             dsdf5=dsdHsbw*er4*((1.125d0/Hsbw2)-(Ah/DHsbw3))
             drdf5=drdHsbw*er4*((1.125d0/Hsbw2)-(Ah/DHsbw3))

             f6   =er5*(3.d0*srpi*(3.d0*DHsbw52*(9.d0*Hsbw-2.d0*Ah)+4.d0*Hsbw32*A2))/(32.d0*DHsbw52*Hsbw32*Ah)
             dsdf6=dsdHsbw*er5*srpi*((27.d0/(32.d0*Hsbw52))-(81.d0/(64.d0*Hsbw32*Ah))-((15.d0*Ah)/(16.d0*DHsbw72)))
             drdf6=drdHsbw*er5*srpi*((27.d0/(32.d0*Hsbw52))-(81.d0/(64.d0*Hsbw32*Ah))-((15.d0*Ah)/(16.d0*DHsbw72)))

             f7   =er6*(((32.d0*Ah)/DHsbw3+(-36.d0+(81.d0*s2*Hh)/Ah)/Hsbw2))/32.d0
             dsdf7=er6*(3.d0*(27.d0*dsdH*DHsbw4*Hsbw*s2+8.d0*dsdHsbw*Ah*(3.d0*DHsbw4-4.d0*Hsbw3*Ah) &
     &                  +54.d0*DHsbw4*s1*(Hsbw-dsdHsbw*s1)*Hh))/(32.d0*DHsbw4*Hsbw3*Ah)
             drdf7=er6*drdHsbw*((2.25d0/Hsbw3)-((3.d0*Ah)/DHsbw4)-((81.d0*s2*Hh)/(16.d0*Hsbw3*Ah)))

             f8   =er7*(-3.d0*srpi*(-40.d0*Hsbw52*A3+9.d0*DHsbw72*(27.d0*Hsbw2-6.d0*Hsbw*Ah+4.d0*A2))) & 
     &                  /(128.d0*DHsbw72*Hsbw52*A2)
             dsdf8=dsdHsbw*er7*srpi*((135.d0/(64.d0*Hsbw72))+(729.d0/(256.d0*Hsbw32*A2))  &
     &                  -(243.d0/(128.d0*Hsbw52*Ah))-((105.d0*Ah)/(32.d0*DHsbw92)))
             drdf8=drdHsbw*er7*srpi*((135.d0/(64.d0*Hsbw72))+(729.d0/(256.d0*Hsbw32*A2))  &
     &                  -(243.d0/(128.d0*Hsbw52*Ah))-((105.d0*Ah)/(32.d0*DHsbw92)))

             f9   =(324.d0*er6*erb*DHsbw4*Hsbw*Ah+er8*(384.d0*Hsbw3*A3+DHsbw4*(-729.d0*Hsbw2 &
     &                  +324.d0*Hsbw*Ah-288.d0*A2)))/(128.d0*DHsbw4*Hsbw3*A2)
             dsdf9=dsdHsbw*(-((81.d0*er6*erb)/(16.d0*Hsbw3*Ah))+er8*((27.d0/(4.d0*Hsbw4))+(729.d0/(128.d0*Hsbw2*A2)) &
     &                  -(81.d0/(16.d0*Hsbw3*Ah))-((12.d0*Ah/DHsbw5))))
             drdf9=drdHsbw*(-((81.d0*er6*erb)/(16.d0*Hsbw3*Ah))+er8*((27.d0/(4.d0*Hsbw4))+(729.d0/(128.d0*Hsbw2*A2)) &
     &                  -(81.d0/(16.d0*Hsbw3*Ah))-((12.d0*Ah/DHsbw5))))

             t2t9   =f2*w1+f3*w2+f4*w3+f5*w4+f6*w5+f7*w6+f8*w7+f9*w8
             dsdt2t9=dsdf2*w1+dsdf3*w2+dsdf4*w3+dsdf5*w4+dsdf6*w5+dsdf7*w6+dsdf8*w7+dsdf9*w8
             drdt2t9=drdw*f2+drdf2*w1+2.d0*drdw*f3*w1+drdf3*w2+3.d0*drdw*f4*w2+drdf4*w3+4.d0*drdw*f5*w3 &
     &                    +drdf5*w4+5.d0*drdw*f6*w4+drdf6*w5+6.d0*drdw*f7*w5+drdf7*w6+7.d0*drdw*f8*w6 &
     &                    +drdf8*w7+8.d0*drdw*f9*w7+drdf9*w8

             Tm1   =t1+t2t9+t10
             dsdTm1=dsdt1+dsdt2t9+dsdt10
             drdTm1=drdt1+drdt2t9+drdt10

             Fx_hse=-8.d0/9.d0*(Tm1+Tm2+Tm3+Tm4+Tm5)
             dsdfx =-8.d0/9.d0*(dsdTm1+dsdTm2+dsdTm3+dsdTm4+dsdTm5)
             drdfx =-8.d0/9.d0*(drdTm1+drdTm3+drdTm4+drdTm5)

          end if

          E_exchange_pbe_sr=E_exchange_pbe_sr+trho*ex_lda*Fx_hse
   
          Vxc(i,ispin)=Vxc(i,ispin)+Fx*vx_lda+(24.d0*Pi*Kp*Kp*mu*trho**3*g2)/(4.d0*Kp*(trho*kf)**2+mu*g2)**2 &
     &                      -alpha_hf*(Fx_hse*vx_lda+(-4.d0/3.d0*s1/trho*dsdfx+drdfx)*trho*ex_lda)

          rtmp(i)=-18.d0*Pi*Kp*Kp*mu*trho**4/(4.d0*Kp*(trho*kf)**2+mu*g2)**2
          rtmp_sr(i)=-alpha_hf*0.5d0*dsdfx*ex_lda/kf

       end do

       rrrr(n1:n2,1)=rtmp(n1:n2)*gx(n1:n2)+rtmp_sr(n1:n2)
       call mpi_allgatherv(rrrr(n1,1),ir_grid(myrank_g),mpi_real8,rrrr(1,1),ir_grid,id_grid,mpi_real8,comm_grid,ierr)
       rrrr(n1:n2,2)=rtmp(n1:n2)*gy(n1:n2)+rtmp_sr(n1:n2)
       call mpi_allgatherv(rrrr(n1,2),ir_grid(myrank_g),mpi_real8,rrrr(1,2),ir_grid,id_grid,mpi_real8,comm_grid,ierr)
       rrrr(n1:n2,3)=rtmp(n1:n2)*gz(n1:n2)+rtmp_sr(n1:n2)
       call mpi_allgatherv(rrrr(n1,3),ir_grid(myrank_g),mpi_real8,rrrr(1,3),ir_grid,id_grid,mpi_real8,comm_grid,ierr)

       select case(SYStype)
       case default
          do i3=0,ML3-1
          do i2=0,ML2-1
          do i1=0,ML1-1
             i=LLL2(i1,i2,i3)
             do m=-Md,Md
                j1=i1+m
                k1=j1/ML1 ; if ( j1<0 ) k1=(j1+1)/ML1-1
                j1=j1-k1*ML1
                j=LLL2(j1,i2,i3)
                if ( n1<=j .and. j<=n2 ) then
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,1)+rrrr(i,2)*b(2,1)+rrrr(i,3)*b(3,1) )
                end if
                j2=i2+m
                k2=j2/ML2 ; if ( j2<0 ) k2=(j2+1)/ML2-1
                j2=j2-k2*ML2
                j=LLL2(i1,j2,i3)
                if ( n1<=j .and. j<=n2 ) then
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,2)+rrrr(i,2)*b(2,2)+rrrr(i,3)*b(3,2) )
                end if
                j3=i3+m
                k3=j3/ML3 ; if ( j3<0 ) k3=(j3+1)/ML3-1
                j3=j3-k3*ML3
                j=LLL2(i1,i2,j3)
                if ( n1<=j .and. j<=n2 ) then
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,3)+rrrr(i,2)*b(2,3)+rrrr(i,3)*b(3,3) )
                end if
             end do
          end do
          end do
          end do
       case(1,2)
!          do i=1,ML
!             i1=LL2(1,i) ; i2=LL2(2,i) ; i3=LL2(3,i)
!             do m=-Md,Md
!                j=LLL2(i1+m,i2,i3)
!                if ( n1<=j .and. j<=n2 ) then
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,1)+rrrr(i,2)*b(2,1)+rrrr(i,3)*b(3,1) )
!                end if
!                j=LLL2(i1,i2+m,i3)
!                if ( n1<=j .and. j<=n2 ) then
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,2)+rrrr(i,2)*b(2,2)+rrrr(i,3)*b(3,2) )
!                end if
!                j=LLL2(i1,i2,i3+m)
!                if ( n1<=j .and. j<=n2 ) then
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,3)+rrrr(i,2)*b(2,3)+rrrr(i,3)*b(3,3) )
!                end if
!             end do
!          end do
       end select

    end do ! ispin

!
! --- PBE Correlation ---
!

    const1=2.d0**(4.d0/3.d0)-2.d0
    const2=9.d0*(2.d0**(1.d0/3.d0)-1.d0)/4.d0

    do i=n1,n2

!       trho=rho(i,ispin) ; if ( allocated(rhoc) ) trho=trho+rhoc(i)
       trho=rho_tmp(i)

       if ( trho <= small_hse ) cycle

       fz=( (1.d0+zeta(i))**(4.d0/3.d0)+(1.d0-zeta(i))**(4.d0/3.d0)-2.d0 )*const1

       kf=(3.d0*Pi*Pi*trho)**(1.d0/3.d0)

!            rs=( 3.d0/(4.d0*Pi*trho) )**(1.d0/3.d0)
       rs=( 3.d0/(4.d0*Pi*abs(trho)) )**(1.d0/3.d0)

       ec_U=-2.d0*A00*(1.d0+alp10*rs)*log( 1.d0+1.d0/(2.d0*A00*(bt10*sqrt(rs)+bt20*rs+bt30*rs**(3.d0/2.d0)+bt40*rs*rs)) )
       ec_P=-2.d0*A01*(1.d0+alp11*rs)*log( 1.d0+1.d0/(2.d0*A01*(bt11*sqrt(rs)+bt21*rs+bt31*rs**(3.d0/2.d0)+bt41*rs*rs)) )
       alpc=-2.d0*A02*(1.d0+alp12*rs)*log( 1.d0+1.d0/(2.d0*A02*(bt12*sqrt(rs)+bt22*rs+bt32*rs**(3.d0/2.d0)+bt42*rs*rs)) )

       ec_lda=ec_U-alpc*fz*const2*(1.d0-zeta(i)**4)+(ec_P-ec_U)*fz*zeta(i)**4

       phi=0.5d0*( (1.d0+zeta(i))**(2.d0/3.d0)+(1.d0-zeta(i))**(2.d0/3.d0) )

       if ( trho == 0.d0 ) then
          A=0.d0
          T=0.d0
          Hs=0.d0
       else
          T=(gx(i)*gx(i)+gy(i)*gy(i)+gz(i)*gz(i))*Pi/(16.d0*phi**2*kf*trho**2)
!               A=C1/(exp(-ec_lda/(C2*phi**3))-1.d0)
!               Hs=C2*phi**3*log( 1.d0+C1*(T+A*T*T)/(1.d0+A*T+A*A*T*T) )
          Ai=( exp(-ec_lda/(C2*phi**3)) - 1.d0 )/C1
          Hs=C2*phi**3*log( 1.d0+C1*( Ai*Ai*T + Ai*T*T )/( Ai*Ai + Ai*T + T*T ) )
!               tmp=exp(-ec_lda/(C2*phi**3))-1.d0
!               Hs=C2*phi**3*log( 1.d0+C1*(tmp*tmp/T+C1*tmp)/(tmp*tmp/(T*T)+C1*tmp/T+C1*C1) )
       end if

       E_correlation=E_correlation+trho*(ec_lda+Hs)

       deU_dn=-4.d0*Pi/9.d0*rs**4*alp10*ec_U/(1.d0+alp10*rs) &
           &     -4.d0*Pi/9.d0*rs*rs*(1.d0+alp10*rs)*(0.5d0*bt10*sqrt(rs)+bt20*rs+1.5d0*bt30*rs*sqrt(rs)+2.d0*bt40*rs*rs) &
           &                     /(bt10+bt20*sqrt(rs)+bt30*rs+bt40*rs*sqrt(rs))**2 * exp(ec_U/(2.d0*A00*(1.d0+alp10*rs)))
       deP_dn=-4.d0*Pi/9.d0*rs**4*alp11*ec_P/(1.d0+alp11*rs) &
           &     -4.d0*Pi/9.d0*rs*rs*(1.d0+alp11*rs)*(0.5d0*bt11*sqrt(rs)+bt21*rs+1.5d0*bt31*rs*sqrt(rs)+2.d0*bt41*rs*rs) &
           &                     /(bt11+bt21*sqrt(rs)+bt31*rs+bt41*rs*sqrt(rs))**2 * exp(ec_P/(2.d0*A01*(1.d0+alp11*rs)))
       dac_dn=-4.d0*Pi/9.d0*rs**4*alp12*alpc/(1.d0+alp12*rs) &
           &     -4.d0*Pi/9.d0*rs*rs*(1.d0+alp12*rs)*(0.5d0*bt12*sqrt(rs)+bt22*rs+1.5d0*bt32*rs*sqrt(rs)+2.d0*bt42*rs*rs) &
           &                     /(bt12+bt22*sqrt(rs)+bt32*rs+bt42*rs*sqrt(rs))**2 * exp(alpc/(2.d0*A02*(1.d0+alp12*rs)))

       dfz_dz=4.d0/3.d0*( (1.d0+zeta(i))**(4.d0/3.d0)-(1.d0-zeta(i))**(4.d0/3.d0) )*const1

       dec_dz=-alpc*dfz_dz*const2*(1.d0-zeta(i)**4)+4.d0*alpc*fz*const2*zeta(i)**3 &
           &                     +(ec_P-ec_U)*dfz_dz*zeta(i)**4+(ec_P-ec_U)*fz*4.d0*zeta(i)**3

       dphi_dz=( (1.d0+zeta(i))**(-1.d0/3.d0)-(1.d0-zeta(i))**(-1.d0/3.d0) )/3.d0

       if ( trho==0.d0 ) then
          dH_dA=0.d0
          dH_dT=0.d0
       else
!          tmp   = 1.d0 + A*T + A*A*T*T
!          dH_dA = -phi**3*C1*C2*A*T**3*(2.d0+A*T)/( tmp*tmp+C1*T*(1.d0+A*T)*tmp )
!          dH_dT =  phi**3*C1*C2*(1.d0+2.d0*A*T)/( tmp*tmp + C1*T*(1.d0+A*T)*tmp )
          tmp   = Ai*Ai + Ai*T + T*T
          dH_dA = -phi**3*C1*C2*Ai*T**3*(2.d0*Ai+T)/( tmp*tmp + C1*T*(Ai*Ai+Ai*T)*tmp ) ! Ai**2 is canceld in dA_dn
          dH_dT =  phi**3*C1*C2*Ai**3*(Ai+2.d0*T)/( tmp*tmp + C1*T*(Ai*Ai+Ai*T)*tmp )
!               tmp1=(exp(-ec_lda/(C2*phi**3))-1.d0)/C1
!               tmp2=tmp1/T
!               dH_dA=-phi**3*C1*C2*tmp1*(2.d0*tmp2+1.d0)/((tmp2*tmp2+tmp2+1.d0)**2+C1*tmp1*(tmp2+1.d0)*(tmp2*tmp2+tmp2+1.d0))
!               dH_dT=phi**3*C1*C2*tmp2**3*(tmp2+2.d0)/((tmp2*tmp2+tmp2+1.d0)**2+tmp1*C1*(tmp2+1.d0)*(tmp2*tmp2+tmp2+1.d0))
       end if

       dH_dphi=3.d0*Hs/phi

       srho(1)    =rho(i,1)     ; if ( flag_pcc_0 ) srho(1)=srho(1)+rhoc(i)/dble(nspin)
       srho(nspin)=rho(i,nspin) ; if ( flag_pcc_0 ) srho(nspin)=srho(nspin)+rhoc(i)/dble(nspin)

       dz_dn(1)    = 2.d0*srho(nspin)/trho
       dz_dn(nspin)=-2.d0*srho(1)/trho

       do ispin=MSP_0,MSP_1

          dec_dn=deU_dn-dac_dn*fz*const2*(1.d0-zeta(i)**4)+(deP_dn-deU_dn)*fz*zeta(i)**4 + dec_dz*dz_dn(ispin)

!               dA_dn=A*(C1+A)/(C1*C2*phi**3)*( dec_dn - 3.d0*ec_lda/phi*dphi_dz*dz_dn(ispin) )
          tmp=exp(-ec_lda/(phi**3*C2))
          dA_dn=tmp/(C1*C2*phi**3)*( dec_dn - 3.d0*ec_lda/phi*dphi_dz*dz_dn(ispin) )

          Vxc(i,ispin)=Vxc(i,ispin) + ec_lda+Hs + trho*dec_dn + trho*dH_dA*dA_dn - 7.d0*T/3.d0*dH_dT &
           &                                         + trho*dH_dphi*dphi_dz*dz_dn(ispin)

       end do

       rtmp(i)=dH_dT*Pi/(8.d0*kf*trho)

    end do

    rrrr(n1:n2,1)=rtmp(n1:n2)*gx(n1:n2)
    call mpi_allgatherv(rrrr(n1,1),ir_grid(myrank_g),mpi_real8,rrrr(1,1),ir_grid,id_grid,mpi_real8,comm_grid,ierr)
    rrrr(n1:n2,2)=rtmp(n1:n2)*gy(n1:n2)
    call mpi_allgatherv(rrrr(n1,2),ir_grid(myrank_g),mpi_real8,rrrr(1,2),ir_grid,id_grid,mpi_real8,comm_grid,ierr)
    rrrr(n1:n2,3)=rtmp(n1:n2)*gz(n1:n2)
    call mpi_allgatherv(rrrr(n1,3),ir_grid(myrank_g),mpi_real8,rrrr(1,3),ir_grid,id_grid,mpi_real8,comm_grid,ierr)

    select case(SYStype)
    case default
       do i3=0,ML3-1
       do i2=0,ML2-1
       do i1=0,ML1-1
          i=LLL2(i1,i2,i3)
          do m=-Md,Md
             j1=i1+m
             k1=j1/ML1 ; if ( j1<0 ) k1=(j1+1)/ML1-1
             j1=j1-k1*ML1
             j=LLL2(j1,i2,i3)
             if ( n1<=j .and. j<=n2 ) then
                do ispin=MSP_0,MSP_1
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,1)+rrrr(i,2)*b(2,1)+rrrr(i,3)*b(3,1) )
                end do
             end if
             j2=i2+m
             k2=j2/ML2 ; if ( j2<0 ) k2=(j2+1)/ML2-1
             j2=j2-k2*ML2
             j=LLL2(i1,j2,i3)
             if ( n1<=j .and. j<=n2 ) then
                do ispin=MSP_0,MSP_1
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,2)+rrrr(i,2)*b(2,2)+rrrr(i,3)*b(3,2) )
                end do
             end if
             j3=i3+m
             k3=j3/ML3 ; if ( j3<0 ) k3=(j3+1)/ML3-1
             j3=j3-k3*ML3
             j=LLL2(i1,i2,j3)
             if ( n1<=j .and. j<=n2 ) then
                do ispin=MSP_0,MSP_1
                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,3)+rrrr(i,2)*b(2,3)+rrrr(i,3)*b(3,3) )
                end do
             end if
          end do
       end do
       end do
       end do
    case(1,2)
!       do i=1,ML
!          i1=LL2(1,i) ; i2=LL2(2,i) ; i3=LL2(3,i)
!          do m=-Md,Md
!             j=LLL2(i1+m,i2,i3)
!             if ( n1<=j .and. j<=n2 ) then
!                do ispin=1,MSP_0,MSP_1
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,1)+rrrr(i,2)*b(2,1)+rrrr(i,3)*b(3,1) )
!                end do
!             end if
!             j=LLL2(i1,i2+m,i3)
!             if ( n1<=j .and. j<=n2 ) then
!                do ispin=MSP_0,MSP_1
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,2)+rrrr(i,2)*b(2,2)+rrrr(i,3)*b(3,2) )
!                end do
!             end if
!             j=LLL2(i1,i2,i3+m)
!             if ( n1<=j .and. j<=n2 ) then
!                do ispin=MSP_0,MSP_1
!                   Vxc(j,ispin)=Vxc(j,ispin)+nab(m)*sign(1,m)*( rrrr(i,1)*b(1,3)+rrrr(i,2)*b(2,3)+rrrr(i,3)*b(3,3) )
!                end do
!             end if
!          end do
!       end do
    end select

    sbf(1)=E_exchange_pbe*dV/dble(nspin)
    sbf(2)=E_exchange_pbe_sr*dV/dble(nspin)
    sbf(3)=E_correlation*dV
    call mpi_allreduce(sbf,rbf,3,mpi_real8,mpi_sum,comm_grid,ierr)
    E_exchange_pbe    = rbf(1)
    E_exchange_pbe_sr = alpha_hf*rbf(2)
    E_correlation     = rbf(3)

!
! --- Short Range Exact Exchange ---
!

    DISP_SWITCH_TMP=DISP_SWITCH_PARALLEL
    DISP_SWITCH_PARALLEL=.false.

    do s=MSP_0,MSP_1
       do k=MBZ_0,MBZ_1
          call rsdft_allgatherv(ML0,MB_0,MB_1,MB &
               ,unk_hf(n1,1,k,s),np_band,comm_band,myrank_b,npart)
       end do
       call rsdft_allgatherv(ML0*MB,MBZ_0,MBZ_1,MBZ &
            ,unk_hf(n1,1,1,s),np_bzsm,comm_bzsm,myrank_k,npart)
    end do

!    call rsdft_allgatherv(ML0*MB*MBZ,MSP_0,MSP_1,Nspin &
!         ,unk(n1,1,1,1),np_spin,comm_spin,myrank_s,npart)

    allocate( trho_hf(n1:n2) ) ; trho_hf=zero
    allocate( tvht(n1:n2)    ) ; tvht=zero

    VFunk(:,:,:,:)=zero

    ctfft=0.0d0
    etfft=0.0d0
    ct_fock_fft(:)=0.0d0
    et_fock_fft(:)=0.0d0

    icount_s=0

    call watch(ctt0,ett0)

    do s=1,nspin

       icount_s=icount_s+1
       irank_s=mod(icount_s-1,np_spin)

       if ( irank_s /= myrank_s ) cycle

       do tr=0,tr_switch ! For time-reversal symmetry  
                     
          icount_k=0  
                     
          do k=1,MBZ

             k_fock(:)=bb(:,1)*kbb(1,k)+bb(:,2)*kbb(2,k)+bb(:,3)*kbb(3,k)
            
             do q=1,k
            
                icount_k=icount_k+1
                irank_k=mod(icount_k-1,np_bzsm)
         
                if ( irank_k /= myrank_k ) cycle
 
                q_fock(:)=bb(:,1)*kbb(1,q)+bb(:,2)*kbb(2,q)+bb(:,3)*kbb(3,q)
                if ( tr == 1 ) then
                   q_fock(:)=-q_fock(:)
                end if

                icount_b=0
           
                do n=1,MB

                   if ( k == q ) then
                      MB_switch=n
                   else
                      MB_switch=MB
                   end if

                   do m=1,MB_switch

                      icount_b=icount_b+1
                      irank_b=mod(icount_b-1,np_band)

                      if ( irank_b /= myrank_b ) cycle
#ifdef RSMOL
                      select case(SYStype)
                      case(1,2)

                         if ( tr==0 .and. q==k ) then

                            if ( Ntot(1)==1 ) then ! Case of H atom
                               c=occ(m,q,s)
                            else
                               c=occ_factor*occ(m,q,s)
                            end if

                            do i=n1,n2
                               trho_hf(i)=unk(i,m,q,s)*unk(i,n,k,s)
                            end do
                            call Hse_fock_mol(n1,n2,trho_hf,tvht)
                            do i=n1,n2
                               VFunk(i,n,k,s)=VFunk(i,n,k,s)-c*tvht(i)*unk(i,m,q,s)
                            end do

                            if ( m/=n ) then
                               do i=n1,n2
                                  c=occ_factor*occ(n,q,s)
                                  VFunk(i,m,k,s)=VFunk(i,m,k,s)-c*tvht(i)*unk(i,n,q,s)
                               end do
                            end if

                         end if

                      end select
#else
                      c=occ_factor*occ(m,q,s)
                      if ( tr == 0 ) then
!$OMP parallel do
                         do i=n1,n2
                            trho_hf(i)=conjg(unk_hf(i,m,q,s))*unk_hf(i,n,k,s)
                         end do
!$OMP end parallel do
                      else
!$OMP parallel do
                         do i=n1,n2
                            trho_hf(i)=unk_hf(i,m,q,s)*unk_hf(i,n,k,s)
                         end do
!$OMP end parallel do
                      end if
                      call watch(ct0,et0)
                      call Fock_fft(n1,n2,k_fock,q_fock,trho_hf,tvht,tr)
!                     call Fock_fft_parallel(n1,n2,k_fock,q_fock,trho_hf,tvht,tr)
                      call watch(ct1,et1) ; ctfft=ctfft+ct1-ct0 ; etfft=etfft+et1-et0
                      if ( tr == 0 ) then
!$OMP parallel do
                         do i=n1,n2
                            VFunk(i,n,k,s)=VFunk(i,n,k,s)-c*tvht(i)*unk_hf(i,m,q,s)
                         end do
!$OMP end parallel do
                      else
!$OMP parallel do
                         do i=n1,n2
                            VFunk(i,n,k,s)=VFunk(i,n,k,s)-c*tvht(i)*conjg(unk_hf(i,m,q,s))
                         end do
!$OMP end parallel do
                      end if

                      if ( m /= n .and. q == k ) then
                         c=occ_factor*occ(n,q,s)
                         if ( tr == 0 ) then
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,m,k,s)=VFunk(i,m,k,s)-c*conjg(tvht(i))*unk_hf(i,n,q,s)
                            end do
!$OMP end parallel do
                         else
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,m,k,s)=VFunk(i,m,k,s)-c*tvht(i)*conjg(unk_hf(i,n,q,s))
                            end do
!$OMP end parallel do
                         end if
                      end if
   
                      if ( m == n .and. q /= k ) then
                         c=occ_factor*occ(m,k,s)
                         if ( tr == 0 ) then
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,n,q,s)=VFunk(i,n,q,s)-c*conjg(tvht(i))*unk_hf(i,m,k,s)
                            end do
!$OMP end parallel do
                         else
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,n,q,s)=VFunk(i,n,q,s)-c*tvht(i)*conjg(unk_hf(i,m,k,s))
                            end do
!$OMP end parallel do
                         end if
                      end if

                      if ( m /= n .and. q /= k ) then
                         c=occ_factor*occ(n,k,s)
                         if ( tr == 0 ) then
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,m,q,s)=VFunk(i,m,q,s)-c*conjg(tvht(i))*unk_hf(i,n,k,s)
                            end do
!$OMP end parallel do
                         else
!$OMP parallel do
                            do i=n1,n2
                               VFunk(i,m,q,s)=VFunk(i,m,q,s)-c*tvht(i)*conjg(unk_hf(i,n,k,s))
                            end do
!$OMP end parallel do
                         end if
                      end if
#endif   
                   end do ! m
                end do ! n

             end do ! q
          end do ! k

       end do ! tr

       call rsdft_allreduce(comm_band,comm_bzsm,VFunk,size(VFunk),reduce_num)

    end do ! s

    call watch(ctt1,ett1)

    deallocate( tvht )
    deallocate( trho_hf )

!
! --- Exact Exchange Energy ---
!

    sum0=0.d0
    do s=MSP_0,MSP_1
       do k=MBZ_0,MBZ_1
          do n=MB_0,MB_1
             if ( abs(occ(n,k,s)) < 1.d-10 ) cycle
             c=0.5d0*occ(n,k,s)
#ifdef RSMOL
             select case(SYStype)
             case(1,2)
                do i=n1,n2
                   sum0=sum0+c*unk(i,n,k,s)*VFunk(i,n,k,s)
                end do
             end select
#else
             do i=n1,n2
                sum0=sum0+c*conjg(unk(i,n,k,s))*VFunk(i,n,k,s)
             end do
#endif
          end do
       end do
    end do

    call watch(ctt2,ett2)

    call mpi_allreduce(sum0,sum1,1,mpi_real8,mpi_sum,comm_grid,ierr)
    call mpi_allreduce(sum1,sum0,1,mpi_real8,mpi_sum,comm_band,ierr)
    call mpi_allreduce(sum0,sum1,1,mpi_real8,mpi_sum,comm_bzsm,ierr)
    call mpi_allreduce(sum1,sum0,1,mpi_real8,mpi_sum,comm_spin,ierr)

    call watch(ctt3,ett3)

    E_exchange_exx=alpha_hf*sum0*dV

!
! --- Exchange Correlation Energy for HSE ---
!

    E_exchange=E_exchange_pbe-E_exchange_pbe_sr+E_exchange_exx
    Exc=E_exchange+E_correlation

    deallocate( zeta )
    deallocate( rho_tmp )
    deallocate( rtmp )
    deallocate( rtmp_sr )
    deallocate( gz,gy,gx )
    deallocate( rrrr )
    select case(SYStype)
    case default
!          call Make_GridMap("deallocate",mem,memax)
       deallocate( LLL2 )
    case(1,2)
!          deallocate(LLL2)
!          deallocate(LL2)
    end select

    DISP_SWITCH_PARALLEL=DISP_SWITCH_TMP

    call watch(ctime1,etime1)

    if ( DISP_SWITCH_PARALLEL ) then
       write(*,*) "TIME(XC_HSE)=",ctime1-ctime0,etime1-etime0
       write(*,'(3x,"Ex,Ec,Exc=",3f20.15)') E_exchange,E_correlation,Exc
       write(*,*) "time(fft)",ctfft,etfft
       write(*,*) "time(fock_fft1)",ct_fock_fft(1),et_fock_fft(1)
       write(*,*) "time(fock_fft2)",ct_fock_fft(2),et_fock_fft(2)
       write(*,*) "time(fock_fft3)",ct_fock_fft(3),et_fock_fft(3)
       write(*,*) "time(fock_fft4)",ct_fock_fft(4),et_fock_fft(4)
       write(*,*) "time(fock_fft5)",ct_fock_fft(5),et_fock_fft(5)
       write(*,*) "time(fock_fft6)",ct_fock_fft(6),et_fock_fft(6)
       write(*,*) "time(fock_fft7)",ct_fock_fft(7),et_fock_fft(7)
       write(*,*) "time(fock_fft8)",ct_fock_fft(8),et_fock_fft(8)
       write(*,*) "time(fock_fft9)",ct_fock_fft(9),et_fock_fft(9)
       write(*,*) "time(fock_fft10)",ct_fock_fft(10),et_fock_fft(10)
       write(*,*) "(1)",ctt1-ctt0
       write(*,*) "(2)",ctt2-ctt1
       write(*,*) "(3)",ctt3-ctt2
    end if

    return
#endif
  END SUBROUTINE calc_xc_hse


  SUBROUTINE Make_GridMap(LLL)
    implicit none
    integer,intent(OUT) :: LLL(-Md:,-Md:,-Md:)
    integer,allocatable :: Igrid_tot(:,:,:)
    integer :: ierr,i,i1,i2,i3,n,j1,j2,j3
    allocate( Igrid_tot(2,3,0:np_grid-1) )
    Igrid_tot=0
    Igrid_tot(1:2,1:3,myrank_g)=Igrid(1:2,1:3)
    call MPI_ALLGATHER(Igrid_tot(1,1,myrank_g),6,MPI_INTEGER &
         ,Igrid_tot,6,MPI_INTEGER,comm_grid,ierr)
    i=0
    do n=0,np_grid-1
       do i3=Igrid_tot(1,3,n),Igrid_tot(2,3,n)
       do i2=Igrid_tot(1,2,n),Igrid_tot(2,2,n)
       do i1=Igrid_tot(1,1,n),Igrid_tot(2,1,n)
          i=i+1
          LLL(i1,i2,i3)=i
       end do
       end do
       end do
    end do
    deallocate( Igrid_tot )
    do i3=0,Ngrid(3)-1
    do i2=0,Ngrid(2)-1
       do i1=-Md,-1
          j1=mod(i1+Ngrid(1),Ngrid(1))
          LLL(i1,i2,i3)=LLL(j1,i2,i3)
       end do
       do i1=Ngrid(1),Ngrid(1)-1+Md
          j1=mod(i1+Ngrid(1),Ngrid(1))
          LLL(i1,i2,i3)=LLL(j1,i2,i3)
       end do
    end do
    end do
    do i3=0,Ngrid(3)-1
    do i1=0,Ngrid(1)-1
       do i2=-Md,-1
          j2=mod(i2+Ngrid(2),Ngrid(2))
          LLL(i1,i2,i3)=LLL(i1,j2,i3)
       end do
       do i2=Ngrid(2),Ngrid(2)-1+Md
          j2=mod(i2+Ngrid(2),Ngrid(2))
          LLL(i1,i2,i3)=LLL(i1,j2,i3)
       end do
    end do
    end do
    do i2=0,Ngrid(2)-1
    do i1=0,Ngrid(1)-1
       do i3=-Md,-1
          j3=mod(i3+Ngrid(3),Ngrid(3))
          LLL(i1,i2,i3)=LLL(i1,i2,j3)
       end do
       do i3=Ngrid(3),Ngrid(3)-1+Md
          j3=mod(i3+Ngrid(3),Ngrid(3))
          LLL(i1,i2,i3)=LLL(i1,i2,j3)
       end do
    end do
    end do
  END SUBROUTINE Make_GridMap

END MODULE xc_hse_module
