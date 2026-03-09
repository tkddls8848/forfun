# Java 설치 (ODL 필수)
sudo apt install -y default-jdk
java -version  # 확인

# ODL 다운로드
wget https://nexus.opendaylight.org/content/repositories/opendaylight.release/org/opendaylight/integration/karaf/0.18.1/karaf-0.18.1.tar.gz
tar -xvf karaf-0.18.1.tar.gz
cd karaf-0.18.1

./bin/karaf

# karaf 콘솔 안에서
opendaylight-user@root> feature:install odl-restconf
opendaylight-user@root> feature:install odl-l2switch-switch
opendaylight-user@root> feature:install odl-mdsal-apidocs
opendaylight-user@root> feature:install odl-dluxapps-applications

# ODL을 외부 컨트롤러로 지정해서 Mininet 실행
sudo mn --topo tree,2 \
        --controller remote,ip=127.0.0.1,port=6633 \
        --switch ovs,protocols=OpenFlow13
```

### ODL 웹 UI 접속
```
브라우저에서: http://localhost:8181/index.html
ID: admin / PW: admin
→ 토폴로지 메뉴에서 Mininet 구성 확인 가능