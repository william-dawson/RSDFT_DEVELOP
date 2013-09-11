MODULE Ggrid_module

  use bb_module, only: bb
  use Rgrid_module, only: Ngrid,Hgrid

  implicit none

  PRIVATE
  PUBLIC :: Gcut,Ecut,NGgrid,LLG,MG_0,MG_1,MGL,NMGL,GG &
           ,allgatherv_Ggrid,construct_NMGL_Ggrid &
           ,get_cutoff_Ggrid,parallel_Ggrid &
           ,construct_Ggrid,destruct_Ggrid

  integer :: NGgrid(0:3),MG_0,MG_1,NMGL
  integer,allocatable :: LLG(:,:),MGL(:)
  integer,allocatable :: ircntg(:),idispg(:)
  real(8),parameter :: ep=1.d-14
  real(8) :: Gcut,Ecut
  real(8),allocatable :: GG(:)

CONTAINS

  SUBROUTINE get_cutoff_Ggrid
    integer :: i,i1,i2,i3,m,n
    real(8) :: b0(3),b1,b2,b3,b12,c,r1,r2,r3
    real(8) :: s,smax
    NGgrid(1)=(Ngrid(1)-1)/2
    NGgrid(2)=(Ngrid(2)-1)/2
    NGgrid(3)=(Ngrid(3)-1)/2
!    Gcut=min( pi/Hgrid(1), pi/Hgrid(2), pi/Hgrid(3) )
    b1=sqrt(sum(bb(1:3,1)**2))*(2*NGgrid(1)+1)
    b2=sqrt(sum(bb(1:3,2)**2))*(2*NGgrid(2)+1)
    b3=sqrt(sum(bb(1:3,3)**2))*(2*NGgrid(3)+1)
    b12=sum(bb(1:3,1)*bb(1:3,2))
    c=b12/(b1*b2)*(2*NGgrid(1)+1)*(2*NGgrid(2)+1)
    s=sqrt(1.d0-c**2)
    r1=s*b1
    r2=s*b2
    b0(1)=bb(2,1)*bb(3,2)-bb(3,1)*bb(2,2)
    b0(2)=bb(3,1)*bb(1,2)-bb(1,1)*bb(3,2)
    b0(3)=bb(1,1)*bb(2,2)-bb(2,1)*bb(1,2)
    r3=abs( sum(bb(1:3,3)*b0(1:3))*(2*NGgrid(3)+1)/sqrt(sum(b0**2)) )
    Gcut=min(r1,r2,r3)*0.5d0
    Ecut=Gcut**2
    m=0
    n=0
    smax=0.d0
    do i3=-(Ngrid(3)-1)/2,(Ngrid(3)-1)/2
    do i2=-(Ngrid(2)-1)/2,(Ngrid(2)-1)/2
    do i1=-(Ngrid(1)-1)/2,(Ngrid(1)-1)/2
       s=(bb(1,1)*i1+bb(1,2)*i2+bb(1,3)*i3)**2 &
        +(bb(2,1)*i1+bb(2,2)*i2+bb(2,3)*i3)**2 &
        +(bb(3,1)*i1+bb(3,2)*i2+bb(3,3)*i3)**2
       m=m+1
       if ( s < Ecut-ep ) n=n+1
       smax=max(s,smax)
    end do
    end do
    end do
    NGgrid(0)=n
    MG_0=1
    MG_1=NGgrid(0)
  END SUBROUTINE get_cutoff_Ggrid


  SUBROUTINE construct_Ggrid(itype)
    integer,intent(IN) :: itype
    integer :: i1,i2,i3,n
    real(8) :: s
    select case(itype)
    case default
       stop 'construct_Ggrid'
    case(0)
       allocate( LLG(3,NGgrid(0)) )
       LLG=0
       n=0
       do i3=-(Ngrid(3)-1)/2,(Ngrid(3)-1)/2
       do i2=-(Ngrid(2)-1)/2,(Ngrid(2)-1)/2
       do i1=-(Ngrid(1)-1)/2,(Ngrid(1)-1)/2
          s=(bb(1,1)*i1+bb(1,2)*i2+bb(1,3)*i3)**2 &
           +(bb(2,1)*i1+bb(2,2)*i2+bb(2,3)*i3)**2 &
           +(bb(3,1)*i1+bb(3,2)*i2+bb(3,3)*i3)**2
          if ( s < Ecut-ep ) then
             n=n+1
             LLG(1,n)=i1
             LLG(2,n)=i2
             LLG(3,n)=i3
          end if
       end do
       end do
       end do
    case(1)
       allocate( LLG(3,MG_0:MG_1) )
       LLG=0
       n=0
       do i3=-(Ngrid(3)-1)/2,(Ngrid(3)-1)/2
       do i2=-(Ngrid(2)-1)/2,(Ngrid(2)-1)/2
       do i1=-(Ngrid(1)-1)/2,(Ngrid(1)-1)/2
          s=(bb(1,1)*i1+bb(1,2)*i2+bb(1,3)*i3)**2 &
           +(bb(2,1)*i1+bb(2,2)*i2+bb(2,3)*i3)**2 &
           +(bb(3,1)*i1+bb(3,2)*i2+bb(3,3)*i3)**2
          if ( s < Ecut-ep ) then
             n=n+1
             if ( MG_0 <= n .and. n <= MG_1 ) then
                LLG(1,n)=i1
                LLG(2,n)=i2
                LLG(3,n)=i3
             end if
          end if
       end do
       end do
       end do
    case(2)
       allocate( LLG(3,NGgrid(0)) )
       LLG=0
       n=0
       do i3=-(Ngrid(3)-1)/2,(Ngrid(3)-1)/2
       do i2=-(Ngrid(2)-1)/2,(Ngrid(2)-1)/2
       do i1=-(Ngrid(1)-1)/2,(Ngrid(1)-1)/2
          s=(bb(1,1)*i1+bb(1,2)*i2+bb(1,3)*i3)**2 &
           +(bb(2,1)*i1+bb(2,2)*i2+bb(2,3)*i3)**2 &
           +(bb(3,1)*i1+bb(3,2)*i2+bb(3,3)*i3)**2
          if ( s < Ecut-ep ) then
             n=n+1
             LLG(1,n) = mod( Ngrid(1)+i1, Ngrid(1) )
             LLG(2,n) = mod( Ngrid(2)+i2, Ngrid(2) )
             LLG(3,n) = mod( Ngrid(3)+i3, Ngrid(3) )
          end if
       end do
       end do
       end do
    end select
  END SUBROUTINE construct_Ggrid


  SUBROUTINE destruct_Ggrid
    deallocate( LLG )
  END SUBROUTINE destruct_Ggrid


  SUBROUTINE construct_NMGL_Ggrid
    integer :: i1,i2,i3,n
    integer,allocatable :: indx(:)
    real(8) :: s1,s2
    real(8),allocatable :: g2(:)
    allocate( MGL(NGgrid(0))  ) ; MGL=0
    allocate( indx(NGgrid(0)) ) ; indx=0
    allocate( g2(NGgrid(0))   ) ; g2=0.d0
    n=0
    do i3=-NGgrid(3),NGgrid(3)
    do i2=-NGgrid(2),NGgrid(2)
    do i1=-NGgrid(1),NGgrid(1)
       s2=(bb(1,1)*i1+bb(1,2)*i2+bb(1,3)*i3)**2 &
         +(bb(2,1)*i1+bb(2,2)*i2+bb(2,3)*i3)**2 &
         +(bb(3,1)*i1+bb(3,2)*i2+bb(3,3)*i3)**2
       if ( s2 < Ecut-ep ) then
          n=n+1
          g2(n)=s2
       end if
    end do
    end do
    end do
    call indexx(NGgrid(0),g2,indx)
    s1=0.d0
    n=1
    do i1=1,NGgrid(0)
       i2=indx(i1)
       s2=g2(i2)
       if ( abs(s2-s1)>1.d-12 ) then
          n=n+1
          s1=s2
       end if
       MGL(i2)=n
    end do
    NMGL=n
    allocate( GG(NMGL) ) ; GG=0.d0
    s1=0.d0
    n=1
    do i1=1,NGgrid(0)
       i2=indx(i1)
       s2=g2(i2)
       if ( abs(s2-s1)>1.d-12 ) then
          n=n+1
          s1=s2
       end if
       GG(n)=s2
    end do
    deallocate( g2 )
    deallocate( indx )
  END SUBROUTINE construct_NMGL_Ggrid


  SUBROUTINE parallel_Ggrid(nprocs,myrank)
    integer,intent(IN) :: nprocs,myrank
    integer :: i,n
    integer,allocatable :: np(:)
    allocate( ircntg(0:nprocs-1) )
    allocate( idispg(0:nprocs-1) )
    allocate( np(0:nprocs-1) )
    np=0
    do i=1,NGgrid(0)
       n=mod(i-1,nprocs)
       np(n)=np(n)+1
    end do
    do n=0,nprocs-1
       idispg(n)=sum( np(0:n) )-np(n)
       ircntg(n)=np(n)
    end do
    deallocate( np )
    MG_0 = idispg(myrank) + 1
    MG_1 = idispg(myrank) + ircntg(myrank)
  END SUBROUTINE parallel_Ggrid


  SUBROUTINE allgatherv_Ggrid(f)
    complex(8),intent(INOUT) :: f(*)
    include 'mpif.h'
    integer :: ierr
    call mpi_allgatherv(f(MG_0),MG_1-MG_0+1,MPI_COMPLEX16 &
         ,f,ircntg,idispg,MPI_COMPLEX16,MPI_COMM_WORLD,ierr)
  END SUBROUTINE allgatherv_Ggrid


END MODULE Ggrid_module
