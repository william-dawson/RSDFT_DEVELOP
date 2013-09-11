MODULE init_ps_nloc2_module

  use pseudopot_module

  implicit none

  PRIVATE
  PUBLIC :: rad1,dviod,read_ps_nloc2,send_ps_nloc2 &
           ,init_ps_nloc2,init_derivative_ps_nloc2

  real(8),allocatable :: rad1(:,:),dviod(:,:,:)
  real(8) :: rcfac,qcfac,etafac

CONTAINS


  SUBROUTINE read_ps_nloc2(unit)
    integer,intent(IN) :: unit
    read(unit,*) rcfac,qcfac,etafac
    write(*,*) "rcfac, qcfac =",rcfac,qcfac
    write(*,*) "etafac       =",etafac
  END SUBROUTINE read_ps_nloc2


  SUBROUTINE send_ps_nloc2(rank)
    integer,intent(IN) :: rank
    integer :: ierr
    include 'mpif.h'
    call mpi_bcast(rcfac  ,1,mpi_real8,rank,mpi_comm_world,ierr)
    call mpi_bcast(qcfac  ,1,mpi_real8,rank,mpi_comm_world,ierr)
    call mpi_bcast(etafac ,1,mpi_real8,rank,mpi_comm_world,ierr)
  END SUBROUTINE send_ps_nloc2


  SUBROUTINE init_ps_nloc2(qcut)
    use atom_module, only: Nelement,Natom,ki_atom
    use maskfunction_module
    real(8),intent(IN) :: qcut
    integer :: i,j,ik,iorb,L,m,m0,m1,m2,MMr,NRc,iloc(1)
    integer,allocatable :: NRps0(:,:)
    real(8),parameter :: dr=2.d-3
    real(8) :: qc,Rc,sum0,const
    real(8) :: x,y,y0,dy,dy0,maxerr
    real(8) :: r,r1,sb0x,sb0y,sb1x,sb1y
    real(8),allocatable :: vrad(:),tmp(:),wm(:,:,:),Rps0(:,:),vtmp(:,:,:)

    qc = qcut*qcfac
    if ( qc<=0.d0 ) qc=qcut

    m=maxval( norb )
    allocate( NRps0(m,Nelement)  ) ; NRps0=0
    allocate(  Rps0(m,Nelement)  ) ;  Rps0=0.d0
    NRps0(:,:)=NRps(:,:)
     Rps0(:,:)= Rps(:,:)

    do ik=1,Nelement
       MMr=Mr(ik)
       do iorb=1,norb(ik)
          Rc=Rps(iorb,ik)*rcfac
          iloc=minloc( abs(rad(1:MMr,ik)-Rc) )
          NRc=iloc(1) ; if ( rad(NRc,ik)<Rc ) NRc=NRc+1
          if ( NRc>MMr ) then
             write(*,*) "NRc,MMr=",NRc,MMr
             stop "rcfac is too large."
          end if
          NRps(iorb,ik)=NRc
          Rps(iorb,ik)=rad(NRc,ik)
       end do
    end do

    NRc=maxval( NRps )
    m=maxval( norb )
    allocate( wm(NRc,m,Nelement) )

    do ik=1,Nelement
       do iorb=1,norb(ik)
          NRc=NRps(iorb,ik)
          Rc=Rps(iorb,ik)
          call makemaskf(etafac)
          maxerr=0.d0
          do i=1,NRc
             x=rad(i,ik)/Rc
             if ( x<=dxm ) then
                y0=1.d0 ; dy0=0.d0
             else
                m0=int(x/dxm)
                dy0=1.d10
                do m=1,20
                   m1=max(m0-m,1) ; m2=min(m0+m,nmsk)
                   call polint(xm(m1),maskr(m1),m2-m1+1,x,y,dy)
                   if ( abs(dy)<dy0 ) then
                      y0=y ; dy0=abs(dy)
                   end if
                end do
             end if
             wm(i,iorb,ik)=y0
             maxerr=max(maxerr,dy0)
          end do
       end do
    end do

    do ik=1,Nelement
       do iorb=1,norb(ik)
          NRps(iorb,ik)=Rps(iorb,ik)/dr+1
          if ( (NRps(iorb,ik)-1)*dr < Rps(iorb,ik) ) then
             NRps(iorb,ik)=NRps(iorb,ik)+1
          end if
       end do
    end do
    MMr=max( maxval(Mr),maxval(NRps) )

    if ( MMr>maxval(Mr) ) then
       m0=size(viod,1)
       m1=size(viod,2)
       m2=size(viod,3)
       allocate( vtmp(m0,m1,m2) )
       vtmp=viod
       deallocate( viod )
       allocate( viod(MMr,m1,m2) ) ; viod=0.d0
       viod(1:m0,1:m1,1:m2) = vtmp(1:m0,1:m1,1:m2)
       deallocate( vtmp )
    end if

    allocate( rad1(MMr,Nelement) ) ; rad1=0.d0
    do ik=1,Nelement
       do i=1,MMr
          rad1(i,ik)=(i-1)*dr
       end do
    end do

    NRc=maxval(NRps0)
    allocate( vrad(NRc),tmp(NRc) )

    const=2.d0/acos(-1.d0)

    do ik=1,Nelement
       do iorb=1,norb(ik)
          L=lo(iorb,ik)
          NRc=NRps0(iorb,ik)
          vrad(1:NRc)=rad(1:NRc,ik)*viod(1:NRc,iorb,ik) &
                     *rab(1:NRc,ik)/wm(1:NRc,iorb,ik)
          do i=1,NRps(iorb,ik)

             r=rad1(i,ik)
             tmp(:)=0.d0

             select case(L)
             case(0)
                if ( r==0.d0 ) then
                   r1=rad(1,ik)
                   if ( r1==0.d0 ) then
                      tmp(1)=qc*qc*qc/3.d0
                   else
                      tmp(1)=sin(qc*r1)/(r1*r1*r1)-qc*cos(qc*r1)/(r1*r1)
                   end if
                   do j=2,NRc
                      r1=rad(j,ik)
                      tmp(j)=sin(qc*r1)/(r1*r1*r1)-qc*cos(qc*r1)/(r1*r1)
                   end do
                else
                   do j=1,NRc
                      r1=rad(j,ik)
                      if ( r1==0.d0 ) then
                         tmp(j)=sin(qc*r)/(r*r*r)-qc*cos(qc*r)/(r*r)
                      else if ( r1==r ) then
                         tmp(j)=(2*qc*r-sin(2.d0*qc*r))/(4*r*r*r)
                      else
                         tmp(j)=( sin(qc*(r-r1))/(r-r1) &
                                 -sin(qc*(r+r1))/(r+r1) )/(2.d0*r*r1)
                      end if
                   end do
                end if
             case(1)
                if ( r==0.d0 ) then
                   viod(i,iorb,ik)=0.d0
                   cycle
                else
                   do j=1,NRc
                      r1=rad(j,ik)
                      if ( r1==0.d0 ) then
                         tmp(j)=0.d0
                      else if ( r1==r ) then
                         sb0x=sin(qc*r)/(qc*r)
                         sb1x=sb0x/(qc*r)-cos(qc*r)/(qc*r)
                         tmp(j)=(2*qc*r-sin(2.d0*qc*r))/(4*r*r*r) &
                              -qc*qc*sb0x*sb1x/r
                      else
                         sb0x=sin(qc*r)/(qc*r)
                         sb0y=sin(qc*r1)/(qc*r1)
                         sb1x=sb0x/(qc*r)-cos(qc*r)/(qc*r)
                         sb1y=sb0y/(qc*r1)-cos(qc*r1)/(qc*r1)
                         tmp(j)=( r1*sb0y*sb1x-r*sb0x*sb1y )*qc*qc/(r*r-r1*r1)
                      end if
                   end do
                end if
             case(2)
                if ( r==0.d0 ) then
                   viod(i,iorb,ik)=0.d0
                   cycle
                else
                   do j=1,NRc
                      r1=rad(j,ik)
                      if ( r1==0.d0 ) then
                         tmp(j)=0.d0
                      else if ( r1==r ) then
                         sb1x=sin(qc*r)/(qc*qc*r*r)-cos(qc*r)/(qc*r)
                         tmp(j)=(2.d0*qc*r-sin(2.d0*qc*r))/(4.d0*r*r*r) &
                              -3.d0*qc*sb1x*sb1x/(r*r)
                      else
                         sb0x=sin(qc*r)/(qc*r)
                         sb0y=sin(qc*r1)/(qc*r1)
                         sb1x=sb0x/(qc*r)-cos(qc*r)/(qc*r)
                         sb1y=sb0y/(qc*r1)-cos(qc*r1)/(qc*r1)
                         tmp(j)=( r*sb0y*sb1x-r1*sb0x*sb1y ) &
                              *qc*qc/(r*r-r1*r1)-3.d0*qc/(r*r1)*sb1x*sb1y
                      end if
                   end do
                end if
             case default
                write(*,*) "PP for L>2 is not implemented."
                stop
             end select
             tmp(1:NRc)=tmp(1:NRc)*vrad(1:NRc)
             call simp(tmp(1:NRc),sum0,NRc,2)
             viod(i,iorb,ik)=sum0*const
          end do ! i
       end do ! iorb
    end do ! ik
    deallocate( vrad,tmp )

    do ik=1,Nelement
       do iorb=1,norb(ik)
          L=lo(iorb,ik)
          NRc=NRps(iorb,ik)
          Rc=Rps(iorb,ik)
          call makemaskf(etafac)
          maxerr=0.d0
          do i=1,NRc
             x=(i-1)*dr/Rc
             if ( x<=dxm ) then
                y0=1.d0 ; dy0=0.d0
             else
                m0=int(x/dxm)
                dy0=1.d10
                do m=1,20
                   m1=max(m0-m,1) ; m2=min(m0+m,nmsk)
                   call polint(xm(m1),maskr(m1),m2-m1+1,x,y,dy)
                   if ( abs(dy)<dy0 ) then
                      y0=y ; dy0=abs(dy)
                   end if
                end do
             end if
             if ( maxerr<dy0 ) maxerr=dy0
             viod(i,iorb,ik)=y0*viod(i,iorb,ik)
          end do
       end do
    end do

    deallocate(  Rps0 )
    deallocate( NRps0 )
    deallocate( wm )

  END SUBROUTINE init_ps_nloc2


  SUBROUTINE init_derivative_ps_nloc2
    use atom_module, only: Nelement
    integer :: ik,L,NRc,J,iorb,i,m,m1,m2,lm
    real(8) :: maxerr,y,dy,y0,dy0
    real(8) :: pi4,const
    real(8),allocatable :: dvrad(:,:,:)

    pi4 = 4.d0*acos(-1.d0)

    lm=0
    do ik=1,Nelement
       m=0
       do iorb=1,norb(ik)
          if ( lo(iorb,ik)==0 ) then
             m=m+1
          else
             m=m+3
          end if
       end do
       lm=max(m,lm)
    end do
    NRc=maxval(NRps)

    allocate( dviod(NRc,lm,Nelement) )
    dviod=0.d0

    do ik=1,Nelement
       do iorb=1,norb(ik)
          L=lo(iorb,ik)
          NRc=NRps(iorb,ik)
          maxerr=0.d0
          do i=1,NRc
             dy0=1.d10
             do m=1,20
                m1=max(i-m,1) ; m2=min(i+m,NRc)
                call dpolint( rad1(m1,ik),viod(m1,iorb,ik),m2-m1+1 &
                     ,rad1(i,ik),y,dy )
                if ( abs(dy)<dy0 ) then
                   y0=y ; dy0=abs(dy)
                end if
             end do
             dviod(i,iorb,ik)=y0
             maxerr=max(maxerr,dy0)
          end do
       end do
    end do

    NRc=maxval(NRps)
    allocate( dvrad(NRc,lm,Nelement) ) ; dvrad=0.d0

    do ik=1,Nelement
       lm=0
       do iorb=1,norb(ik)
          L=lo(iorb,ik)
          NRc=NRps(iorb,ik)
          do J=abs(L-1),L+1
             lm=lm+1
             const=0.5d0*(2.d0+L*(L+1)-J*(J+1))
             do i=1,NRc
                dvrad(i,lm,ik)=rad1(i,ik)**2*dviod(i,iorb,ik) &
                     +const*rad1(i,ik)*viod(i,iorb,ik)
             end do
          end do
       end do
    end do
    const=sqrt(pi4/3.d0)
    do ik=1,Nelement
       lm=0
       do iorb=1,norb(ik)
          L=lo(iorb,ik)
          NRc=NRps(iorb,ik)
          do J=abs(L-1),L+1
             lm=lm+1
             do i=1,NRc
                dviod(i,lm,ik)=const*dvrad(i,lm,ik)
             end do
          end do
       end do
    end do

    deallocate( dvrad )

  END SUBROUTINE init_derivative_ps_nloc2


  SUBROUTINE simp(f,s,n,m)
    integer,intent(IN)  :: n,m
    real(8),intent(IN)  :: f(n)
    real(8),intent(OUT) :: s
    real(8),allocatable :: g(:)
    integer :: i,nn,nmax
    nmax=int(n/m)*m
    do i=0,m
       nmax=nmax+i ; if ( nmax>=n ) exit
    end do
    allocate( g(nmax) ) ; g(1:n)=f ; if ( nmax>n ) g(n+1:)=0.d0
    select case(m)
    case default
       s = 0.5d0*(f(1)+f(n)) + sum(f(2:n-1))
    case(2)
       s=0.d0
       do i=1,nmax-2,2
          s = s + g(i) + 4.d0*g(i+1) + g(i+2)
       end do
       s=s/3.d0
    case(4)
       s=0.d0
       do i=1,nmax-4,4
          s=s+7*g(i)+32*g(i+1)+12*g(i+2)+32*g(i+3)+7*g(i+4)
       end do
       s=s*2.d0/45.d0
    case(6)
       s=0.d0
       do i=1,nmax-6,6
          s=s+41*g(i)+216*g(i+1)+27*g(i+2)+272*g(i+3) &
               +27*g(i+4)+216*g(i+5)+41*g(i+6)
       end do
       s=s/140.d0
    end select
    deallocate( g )
    return
  END SUBROUTINE simp


END MODULE init_ps_nloc2_module
