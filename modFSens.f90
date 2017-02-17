module modFSens

	use modBC
	use modRecord

	implicit none

	type FSens
		type(PM1D) :: dpm
		real(mp) :: Lv, dv
		integer :: ngv
		real(mp), allocatable :: j(:,:), f_A(:,:)
		integer :: NInject										!Number of injecting particle per direction
		integer :: NLimit											!Number limit of particle for redistribution
	contains
		procedure, pass(this) :: buildFSens
		procedure, pass(this) :: destroyFSens
		procedure, pass(this) :: FSensSourceTerm
		procedure, pass(this) :: InjectSource
		procedure, pass(this) :: FSensDistribution
		procedure, pass(this) :: Redistribute
		procedure, pass(this) :: updateWeight
	end type

contains

	subroutine buildFSens(this,pm,Lv,Ngv,NInject,NLimit)
		class(FSens), intent(out) :: this
		type(PM1D), intent(in) :: pm
		real(mp), intent(in) :: Lv
		integer, intent(in) :: Ngv, NInject, NLimit
		integer :: i

		call this%dpm%buildPM1D(pm%nt*pm%dt,pm%ni*pm%dt,pm%ng,pm%n,	&
							pm%pBCindex,pm%mBCindex,pm%a(1)%order,	&
							pm%dt,pm%L,pm%A0,pm%eps0)
		do i=1,pm%n
			call this%dpm%p(i)%buildSpecies(pm%p(i)%qs,pm%p(i)%ms)
		end do
		call this%dpm%m%setMesh(pm%m%rho_back)

		this%NInject = NInject
		this%NLimit = NLimit
		this%Lv = Lv
		this%ngv = Ngv
		this%dv = Lv/Ngv
		allocate(this%j(pm%ng,2*Ngv+1))
		allocate(this%f_A(pm%ng,2*Ngv+1))
	end subroutine

	subroutine destroyFSens(this)
		class(FSens), intent(inout) :: this
		integer :: i

		call destroyPM1D(this%dpm)
		deallocate(this%j)
		deallocate(this%f_A)
	end subroutine

	subroutine FSensSourceTerm(this,pm,nk,fsr)
		class(FSens), intent(inout) :: this
		type(PM1D), intent(in) :: pm
		integer, intent(in), optional :: nk
		type(recordData), intent(in), optional :: fsr
		integer :: kr
		character(len=100) :: kstr
		integer :: i,k, g(pm%a(1)%order+1)
		integer :: vgl, vgr
		real(mp) :: vp, g0, h

		!F to phase space
		this%j = 0.0_mp
		do i=1,pm%n
			do k = 1, pm%p(i)%np
				vp = pm%p(i)%vp(k,1)
				g0 = FLOOR(vp/this%dv)
				vgl = g0 + this%ngv+1
				vgr = vgl+1
				if( vgl<1 .or. vgr>2*this%ngv+1 )	cycle
				g = pm%a(i)%g(k,:)
				h = vp/this%dv - g0
				this%j(g,vgl) = this%j(g,vgl) + (1.0_mp-h)*pm%p(i)%spwt(k)/pm%m%dx/this%dv*pm%a(i)%frac(k,:)
				this%j(g,vgr) = this%j(g,vgr) + h*pm%p(i)%spwt(k)/pm%m%dx/this%dv*pm%a(i)%frac(k,:)
			end do
			this%j(:,1) = this%j(:,1)*2.0_mp
			this%j(:,2*this%ngv+1) = this%j(:,2*this%ngv+1)*2.0_mp
		end do

		!Gradient in v direction
		do i=1,pm%m%ng
			this%j(i,2:2*this%ngv) = ( this%j(i,3:2*this%ngv+1)-this%j(i,1:2*this%ngv-1) )/2.0_mp/this%dv
		end do
		this%j(:,1) = 0.0_mp
		this%j(:,pm%m%ng) = 0.0_mp
		if( present(nk) ) then
			if( (fsr%mod.eq.1) .or. (mod(nk,fsr%mod).eq.0) ) then
				kr = merge(nk,nk/fsr%mod,fsr%mod.eq.1)
				write(kstr,*) kr
				open(unit=305,file='data/'//fsr%dir//'/Dvf_'//trim(adjustl(kstr))//'.bin',	&
						status='replace',form='unformatted',access='stream')
				write(305) this%j
				close(305)
			end if
		end if

		!Multiply E_A
		do i=1,2*this%ngv+1
			this%j(:,i) = this%j(:,i)*this%dpm%m%E
		end do

		!Multiply dt
		this%j = this%j*pm%dt
	end subroutine

	subroutine InjectSource(this,f,N)
		class(FSens), intent(inout) :: this
		real(mp), intent(in), dimension(this%dpm%m%ng,2*this%ngv+1) :: f
		integer, intent(in) :: N
		real(mp), allocatable :: xp0(:), vp0(:,:), spwt0(:)

		call createDistribution(this,f,N,xp0,vp0,spwt0)
		call this%dpm%p(1)%appendSpecies(size(xp0),xp0,vp0,spwt0)
	end subroutine

	subroutine createDistribution(this,f,N,xp0,vp0,spwt0)
		class(FSens), intent(inout) :: this
		real(mp), intent(in), dimension(this%dpm%m%ng,2*this%ngv+1) :: f
		integer, intent(in) :: N
		real(mp), intent(out), allocatable :: xp0(:), vp0(:,:), spwt0(:)
		integer :: Nx, newN
		integer :: i,i1,i2,k,Np,nk
		integer :: vgl, vgr
		real(mp) :: w, h
		real(mp), allocatable :: frac(:,:)
		Nx = INT(SQRT(N*1.0_mp))
		newN = Nx*Nx
!		newN = N

		do i=1,this%dpm%n
			allocate(xp0(newN))
			allocate(vp0(newN,3))
			allocate(spwt0(newN))

			!Spatial distribution: Uniformly-random x dimension
!			call RANDOM_NUMBER(xp0)
!			xp0 = xp0*this%dpm%L
!			!Apply periodic BC
!			do k=1,newN
!				if( xp0(k)<0.0_mp ) then
!					xp0(k) = xp0(k) + this%dpm%L
!				elseif( xp0(k)>this%dpm%L ) then
!					xp0(k) = xp0(k) - this%dpm%L
!				end if
!			end do

			!Velocity distribution: Gaussian-random v dimension
!			vp0 = randn(newN,3)
!			w = 0.4_mp*this%Lv
!			vp0 = vp0*w
			!Velocity distribution: Uniformly-random x999999 dimension
!			call RANDOM_NUMBER(vp0)
!			vp0 = (2.0_mp*vp0-1.0_mp)*this%Lv

			!Uniform grid distribution on phase space
			xp0 = 0.0_mp
			vp0 = 0.0_mp
			spwt0 = 0.0_mp
			do i2=1,Nx
				do i1=1,Nx
					xp0(i1+Nx*(i2-1)) = (i1-0.5_mp)*this%dpm%L/Nx
					vp0(i1+Nx*(i2-1),:) = (i2-0.5_mp)*2.0_mp*this%Lv/Nx - 1.0_mp*this%Lv
				end do
			end do

			!X-direction Interpolation
			call this%dpm%a(i)%assignMatrix(this%dpm%m,xp0)
			!Adjust grid for periodic BC
			do k=1,newN
				if( this%dpm%a(i)%g(k,1)<1 ) then
					this%dpm%a(i)%g(k,1) = this%dpm%a(i)%g(k,1) + this%dpm%m%ng
				elseif( this%dpm%a(i)%g(k,1)>this%dpm%m%ng ) then
					this%dpm%a(i)%g(k,1) = this%dpm%a(i)%g(k,1) - this%dpm%m%ng
				end if
				if( this%dpm%a(i)%g(k,2)<1 ) then
					this%dpm%a(i)%g(k,2) = this%dpm%a(i)%g(k,2) + this%dpm%m%ng
				elseif( this%dpm%a(i)%g(k,2)>this%dpm%m%ng ) then
					this%dpm%a(i)%g(k,2) = this%dpm%a(i)%g(k,2) - this%dpm%m%ng
				end if
			end do

			!V-direction Interpolation and determine spwt
			allocate(frac(this%dpm%a(i)%order+1,2))
			frac = 0.0_mp
			do k=1,newN
				vgl = FLOOR(vp0(k,1)/this%dv) + this%ngv+1
				vgr = vgl+1

				if( vgl<1 .or. vgr>2*this%ngv+1 ) then
					spwt0(k) = 0.0_mp
					cycle
				end if

				h = vp0(k,1)/this%dv - FLOOR(vp0(k,1)/this%dv)
				frac(:,1) = this%dpm%a(i)%frac(k,:)*(1.0_mp-h)
				frac(:,2) = this%dpm%a(i)%frac(k,:)*h
				spwt0(k) = SUM( f(this%dpm%a(i)%g(k,:),(/vgl,vgr/))*frac )	&
!								*this%dpm%L*sqrt(2.0_mp*pi)*w/EXP( -vp0(k,1)**2/2.0_mp/w/w )
								*this%dpm%L*2.0_mp*this%Lv
			end do
			spwt0 = spwt0/newN
		end do
	end subroutine

	subroutine FSensDistribution(this)
		class(FSens), intent(inout) :: this
		integer :: i,k, g(this%dpm%a(1)%order+1)
		integer :: vgl, vgr
		real(mp) :: vp, h

		!F to phase space
		this%f_A = 0.0_mp
		do i = 1, this%dpm%n
			do k = 1, this%dpm%p(i)%np
				vp = this%dpm%p(i)%vp(k,1)
				vgl = FLOOR(vp/this%dv) + this%ngv+1
				vgr = vgl+1
				if( vgl<1 .or. vgr>2*this%ngv+1 )	cycle
				g = this%dpm%a(i)%g(k,:)
				h = vp/this%dv - FLOOR(vp/this%dv)
				this%f_A(g,vgl) = this%f_A(g,vgl) + (1.0_mp-h)*this%dpm%p(i)%spwt(k)/this%dpm%m%dx/this%dv*this%dpm%a(i)%frac(k,:)
				this%f_A(g,vgr) = this%f_A(g,vgr) + h*this%dpm%p(i)%spwt(k)/this%dpm%m%dx/this%dv*this%dpm%a(i)%frac(k,:)
			end do
			this%f_A(:,1) = this%f_A(:,1)*2.0_mp
			this%f_A(:,2*this%ngv+1) = this%f_A(:,2*this%ngv+1)*2.0_mp
		end do
	end subroutine

	subroutine Redistribute(this)
		class(FSens), intent(inout) :: this
		real(mp), allocatable :: xp0(:), vp0(:,:), spwt0(:)
		integer :: i
		if( this%dpm%p(1)%np.ge.INT(1.5_mp*this%NLimit) ) then
			call this%FSensDistribution
			call createDistribution(this,this%f_A,INT(0.5_mp*this%NLimit),xp0,vp0,spwt0)
			call this%dpm%p(1)%setSpecies(size(xp0),xp0,vp0,spwt0)
		end if
	end subroutine

	subroutine updateWeight(this,j)
		class(FSens), intent(inout) :: this
		real(mp), intent(in), dimension(this%dpm%m%ng,2*this%ngv+1) :: j
		real(mp), dimension(this%dpm%m%ng,2*this%ngv+3) :: n_temp
		integer :: i,k, g(this%dpm%a(1)%order+1)
		integer, allocatable :: g_v(:,:)
		real(mp), allocatable :: frac_xv(:,:,:)
		integer :: vgl, vgr, k_temp
		real(mp) :: vp, h

		do i = 1, this%dpm%n
			!F_A to phase space
			n_temp = 0.0_mp
!			this%f_A = 0.0_mp
			allocate(g_v(2,this%dpm%p(i)%np))
			allocate(frac_xv(2,2,this%dpm%p(i)%np))
			do k = 1, this%dpm%p(i)%np
				vp = this%dpm%p(i)%vp(k,1)
!				vgl = FLOOR(vp/this%dv) + this%ngv+1
				vgl = FLOOR(vp/this%dv) + this%ngv+2
				vgr = vgl+1
!				if( vgl<1 .or. vgr>2*this%ngv+1 )	then
				if( vgl<1 .or. vgr>2*this%ngv+3 )	then
					g_v(:,k) = this%ngv+2
					frac_xv(:,:,k) = 0.0_mp
					cycle
				end if
				g = this%dpm%a(i)%g(k,:)
				g_v(:,k) = (/ vgl, vgr /)
				h = vp/this%dv - FLOOR(vp/this%dv)
				frac_xv(:,1,k) = (1.0_mp-h)*this%dpm%a(i)%frac(k,:)
				frac_xv(:,2,k) = h*this%dpm%a(i)%frac(k,:)
!				this%f_A(g,g_v(:,k)) = this%f_A(g,g_v(:,k)) + frac_xv(:,:,k)/this%dpm%m%dx/this%dv
				n_temp(g,g_v(:,k)) = n_temp(g,g_v(:,k)) + frac_xv(:,:,k)/this%dpm%m%dx/this%dv
			end do
			this%f_A = n_temp(:,2:2*this%ngv+2)
!			this%f_A(:,1) = this%f_A(:,1)*2.0_mp
!			this%f_A(:,2*this%ngv+1) = this%f_A(:,2*this%ngv+1)*2.0_mp

			!Adjust grid
			do k = 1, this%dpm%p(1)%np
				if( g_v(1,k).eq.1 ) then
					frac_xv(:,1,k) = 0.0_mp
					g_v(1,k) = this%ngv+2
				end if
				if( g_v(2,k).eq.2*this%ngv+3 ) then
					frac_xv(:,2,k) = 0.0_mp
					g_v(2,k) = this%ngv+2
				end if
			end do
			g_v = g_v-1

			!Update weight
			do k = 1, this%dpm%p(i)%np
				g = this%dpm%a(i)%g(k,:)
				this%dpm%p(i)%spwt(k) = this%dpm%p(i)%spwt(k)	&
													+ SUM( j(g,g_v(:,k))*frac_xv(:,:,k)/this%f_A(g,g_v(:,k)) )
			end do

			deallocate(g_v)
			deallocate(frac_xv)
		end do
	end subroutine

end module
