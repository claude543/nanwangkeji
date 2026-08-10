function [Ppv_max1_kW,Ppv_max2_kW] = PV_Profile_Curve(time_s,P_unit_kW,PV_time_s,PV_profile_pu)
                                                                                              %#codegen                                                                                      
                                                                                              pu = interp_profile(time_s, PV_time_s, PV_profile_pu);                                         
                                                                                              pmax = max(P_unit_kW, 0.0) * max(pu, 0.0);                                                     
                                                                                              Ppv_max1_kW = pmax;                                                                            
                                                                                              Ppv_max2_kW = pmax;                                                                            
                                                                                              end                                                                                            
                                                                                                                                                                                             
                                                                                              function y = interp_profile(t, x, v)                                                           
                                                                                              n = numel(x);                                                                                  
                                                                                              y = v(1);                                                                                      
                                                                                              if t <= x(1)                                                                                   
                                                                                                  return;                                                                                    
                                                                                              end                                                                                            
                                                                                              for k = 1:n-1                                                                                  
                                                                                                  if t <= x(k+1)                                                                             
                                                                                                      dx = max(x(k+1)-x(k), 1e-9);                                                           
                                                                                                      a = (t-x(k))/dx;                                                                       
                                                                                                      y = v(k) + a*(v(k+1)-v(k));                                                            
                                                                                                      return;                                                                                
                                                                                                  end                                                                                        
                                                                                              end                                                                                            
                                                                                              y = v(n);                                                                                      
                                                                                              end                                                                                            
                                                                                              