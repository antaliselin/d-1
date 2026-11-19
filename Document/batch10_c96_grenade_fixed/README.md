# C96与普通手雷局部重绘

基准：../batch09_visibility_tiles/。仅修改03毛瑟C96及15普通手雷，其余90张独立PNG字节一致；第一张合集两处替换区域以外像素一致，第二张合集PNG字节一致。两件仍分别占2格、1格，保留显示上限与自身长宽比。

模型gpt-image-2.5，quality auto；请求4K，接口实际3840×2160。对两件进行独立高分辨率重绘后，本地透明去底、清边、预乘Alpha Lanczos采样与无损替换，无JPEG中间格式。最终PNG保存后重新核验实际Alpha>0包围框宽高均为4的倍数，半透明边缘保留、透明RGB为0、四周至少24px留白。

C96修正为短固定弹仓、扫帚柄木握把、连续机匣与长枪管、明确扳机及护圈，统一宽大切面的光影；普通手雷修正顶部拉环和贴身保险杆连接，保持完整蛋形轮廓和少量大块切面。木柄手雷未修改。

atlas_1/2_3840x2160.png为两张透明合集，individual/为92张PNG，changed_items_*为两件原尺寸深浅背景预览，preview_*为完整预览，grid_*为网格检查；prompt.txt为完整提示词；source.png为接口4K源图；manifest.json、coordinates.csv、validation.json记录坐标及一致性验证。其他物品与历史材质待办保持基准状态。
